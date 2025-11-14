"""User Manager - Handles GitLab OAuth user management within VMs."""

import copy
import json
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from vm_manager import VMManager


class UserManager:
    """Manages users via GitLab OAuth integration."""
    
    def __init__(self):
        self.config_dir = Path.home() / ".config" / "rave"
        self.users_file = self.config_dir / "users.json"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.supported_providers = {"google_oauth2", "github"}
        self.default_provider = "google_oauth2"

    def set_default_provider(self, provider: str):
        """Set the default OAuth provider used when none is provided."""
        self.default_provider = self._normalize_provider(provider)
    
    def _load_users(self) -> Dict:
        """Load users configuration."""
        if not self.users_file.exists():
            return {"users": []}
        try:
            return json.loads(self.users_file.read_text())
        except (json.JSONDecodeError, FileNotFoundError):
            return {"users": []}
    
    def _save_users(self, users_data: Dict):
        """Save users configuration."""
        self.users_file.write_text(json.dumps(users_data, indent=2))
    
    def _find_user(self, users_data: Dict, email: str) -> Optional[Dict]:
        """Find user by email."""
        for user in users_data["users"]:
            if user["email"] == email:
                return user
        return None

    def _normalize_provider(self, provider: Optional[str]) -> str:
        if not provider:
            return self.default_provider

        value = provider.strip()
        if not value:
            return self.default_provider

        key = value.lower()
        if key in {"google", "google_oauth2"}:
            return "google_oauth2"
        if key == "github":
            return "github"
        if key in self.supported_providers:
            return key
        raise ValueError(f"Unsupported OAuth provider: {provider}")

    def _provider_label(self, provider: Optional[str]) -> str:
        normalized = self._normalize_provider(provider)
        if normalized == "google_oauth2":
            return "Google"
        if normalized == "github":
            return "GitHub"
        return normalized

    def _execute_gitlab_command(self, company_vm: str, command: List[str]) -> Dict[str, any]:
        """Execute GitLab management command in VM."""
        # This would SSH into the VM and execute gitlab-rails commands
        vm_manager = VMManager(Path.home() / ".config" / "rave" / "vms")
        config = vm_manager._load_vm_config(company_vm)
        
        if not config:
            return {"success": False, "error": f"VM '{company_vm}' not found"}
        
        if not vm_manager._is_vm_running(company_vm):
            return {"success": False, "error": f"VM '{company_vm}' is not running"}
        
        # Build SSH command to execute GitLab rails command
        ports = config["ports"]
        ruby_script = "\n".join(command)

        ssh_cmd = [
            "ssh", "-i", config["keypair"], "-o", "StrictHostKeyChecking=no",
            "-p", str(ports["ssh"]), "root@localhost",
            "gitlab-rails", "runner", "-"
        ]

        try:
            result = subprocess.run(
                ssh_cmd,
                input=ruby_script,
                capture_output=True,
                text=True,
                check=True
            )
            return {"success": True, "output": result.stdout}
        except subprocess.CalledProcessError as e:
            return {"success": False, "error": f"GitLab command failed: {e.stderr}"}
    
    def add_user(
        self,
        email: str,
        oauth_id: str,
        access: str,
        company: Optional[str] = None,
        *,
        name: Optional[str] = None,
        metadata: Optional[Dict[str, str]] = None,
        update_existing: bool = False,
        provider: Optional[str] = None,
    ) -> Dict[str, any]:
        """Add or update a GitLab OAuth user."""

        access_level = access.lower()
        valid_access = ["admin", "developer", "guest"]
        if access_level not in valid_access:
            return {
                "success": False,
                "error": f"Invalid access level. Use: {', '.join(valid_access)}",
            }

        users_data = self._load_users()
        existing_user = self._find_user(users_data, email)
        is_update = existing_user is not None

        if is_update and not update_existing:
            return {"success": False, "error": f"User {email} already exists"}

        now = time.time()
        incoming_oauth = (oauth_id or "").strip() or email.split("@")[0]

        if is_update and existing_user.get("oauth_id") and existing_user["oauth_id"] != incoming_oauth:
            return {
                "success": False,
                "error": (
                    f"OAuth ID mismatch for {email}: existing {existing_user['oauth_id']}, "
                    f"incoming {incoming_oauth}"
                ),
            }

        if is_update:
            user_record = copy.deepcopy(existing_user)
        else:
            user_record = {
                "email": email,
                "created_at": now,
            }

        user_record["oauth_id"] = (
            existing_user.get("oauth_id") if is_update and existing_user.get("oauth_id") else incoming_oauth
        )
        user_record["access"] = access_level
        user_record.setdefault("created_at", now)
        user_record["updated_at"] = now

        try:
            provider_value = self._normalize_provider(
                provider or user_record.get("provider") or (existing_user or {}).get("provider")
            )
        except ValueError as exc:
            return {"success": False, "error": str(exc)}
        user_record["provider"] = provider_value

        if company is not None:
            user_record["company"] = company

        if name is not None:
            display_name = name.strip()
            if display_name:
                user_record["name"] = display_name
            else:
                user_record.pop("name", None)

        if metadata is not None:
            filtered_metadata = {
                str(k): str(v)
                for k, v in metadata.items()
                if v is not None and str(v).strip()
            }
            if filtered_metadata:
                user_record["metadata"] = filtered_metadata
            else:
                user_record.pop("metadata", None)

        vm_company = company if company is not None else user_record.get("company")
        if vm_company:
            username_base = email.split("@")[0]
            username_base = re.sub(r"[^a-zA-Z0-9_]", "-", username_base)
            if not username_base:
                username_base = "user"

            display_name_literal = (
                json.dumps(user_record.get("name"))
                if user_record.get("name")
                else "nil"
            )

            script_lines = [
                "require 'securerandom'",
                "",
                f"email = {json.dumps(email)}",
                f"oauth_id = {json.dumps(user_record['oauth_id'])}",
                f"provider = {json.dumps(provider_value)}",
                f"username_base = {json.dumps(username_base)}",
                "username = username_base",
                "suffix = 0",
                "while User.exists?(username: username)",
                "  suffix += 1",
                "  username = \"#{username_base}-#{suffix}\"",
                "end",
                f"display_name = {display_name_literal}",
                "",
                "password = SecureRandom.hex(20)",
                "user = User.find_by(email: email)",
                "",
                "if user",
                "  user.external = true",
                "  user.name = display_name if display_name && !display_name.empty?",
                "  if user.encrypted_password.blank?",
                "    user.password = password",
                "    user.password_confirmation = password",
                "  end",
                "  user.skip_confirmation! if user.respond_to?(:skip_confirmation!)",
                "  user.build_namespace(path: username, name: username) unless user.namespace",
                "  user.save!",
                "else",
                "  user = User.new(",
                "    email: email,",
                "    name: display_name || username,",
                "    username: username,",
                "    external: true,",
                "    password: password,",
                "    password_confirmation: password",
                "  )",
                "  user.skip_confirmation! if user.respond_to?(:skip_confirmation!)",
                "  user.build_namespace(path: username, name: username)",
                "  user.save!",
                "end",
                "",
                "identity = user.identities.find_or_initialize_by(provider: provider)",
                "identity.extern_uid = oauth_id",
                "identity.save!",
                "",
                "puts user.id",
            ]

            gitlab_cmd = ["\n".join(script_lines)]
            result = self._execute_gitlab_command(vm_company, gitlab_cmd)
            if not result["success"]:
                return result

        if is_update:
            existing_user.clear()
            existing_user.update(user_record)
        else:
            users_data["users"].append(user_record)

        self._save_users(users_data)

        payload = {"success": True, "user": user_record.copy()}
        if is_update:
            payload["updated"] = True
        else:
            payload["created"] = True
        return payload
    
    def remove_user(self, email: str) -> Dict[str, any]:
        """Remove a user."""
        users_data = self._load_users()
        user = self._find_user(users_data, email)
        
        if not user:
            return {"success": False, "error": f"User {email} not found"}
        
        # Remove from GitLab if company is specified
        if user.get("company"):
            gitlab_cmd = [
                f"user = User.find_by(email: '{email}'); user.destroy if user"
            ]
            
            result = self._execute_gitlab_command(user["company"], gitlab_cmd)
            # Continue even if GitLab removal fails (VM might be down)
        
        # Remove from local database
        users_data["users"] = [u for u in users_data["users"] if u["email"] != email]
        self._save_users(users_data)
        
        return {"success": True}
    
    def list_users(self, company: Optional[str] = None) -> Dict[str, any]:
        """List all users, optionally filtered by company."""
        users_data = self._load_users()
        users = users_data["users"]
        
        for user in users:
            if not user.get("provider"):
                user["provider"] = self.default_provider

        if company:
            users = [u for u in users if u.get("company") == company]
        
        return {"success": True, "users": users}
    
    def get_user(self, email: str) -> Dict[str, any]:
        """Get user details."""
        users_data = self._load_users()
        user = self._find_user(users_data, email)
        
        if not user:
            return {"success": False, "error": f"User {email} not found"}
        
        if not user.get("provider"):
            user["provider"] = self.default_provider

        return {"success": True, "user": user}
    
    def config_user(self, email: str, access: Optional[str] = None) -> Dict[str, any]:
        """Configure user settings."""
        users_data = self._load_users()
        user = self._find_user(users_data, email)
        
        if not user:
            return {"success": False, "error": f"User {email} not found"}
        
        # Update access level
        if access:
            valid_access = ["admin", "developer", "guest"]
            if access not in valid_access:
                return {"success": False, "error": f"Invalid access level. Use: {', '.join(valid_access)}"}
            
            user["access"] = access
            
            # Update in GitLab if company is specified
            if user.get("company"):
                # Map access levels to GitLab access levels
                gitlab_access = {
                    "admin": "50",    # Owner
                    "developer": "30", # Developer
                    "guest": "10"     # Guest
                }
                
                gitlab_cmd = [
                    f"user = User.find_by(email: '{email}'); project = Project.first; project.add_developer(user) if user && project"
                ]
                
                result = self._execute_gitlab_command(user["company"], gitlab_cmd)
                # Continue even if GitLab update fails
        
        # Save updated user data
        self._save_users(users_data)
        
        return {"success": True, "user": user}

    # Enhanced user management features
    
    def bulk_add_users(
        self,
        users_file: str,
        company: Optional[str] = None,
        default_metadata: Optional[Dict[str, str]] = None,
        provider: Optional[str] = None,
    ) -> Dict[str, any]:
        """Add multiple users from CSV/JSON file."""
        file_path = Path(users_file).expanduser()
        if not file_path.exists():
            return {"success": False, "error": f"File not found: {file_path}"}
        
        added_users: List[Dict[str, any]] = []
        updated_users: List[Dict[str, any]] = []
        failed_users: List[Dict[str, any]] = []
        skipped_users: List[Dict[str, any]] = []

        def _clean_metadata(meta: Optional[Dict[str, str]]) -> Optional[Dict[str, str]]:
            if not meta:
                return None
            cleaned = {
                str(k): str(v)
                for k, v in meta.items()
                if v is not None and str(v).strip()
            }
            return cleaned or None

        default_meta_clean = _clean_metadata(default_metadata)

        try:
            normalized_default_provider = self._normalize_provider(provider)
        except ValueError as exc:
            return {"success": False, "error": str(exc)}

        try:
            if file_path.suffix.lower() == '.json':
                import_data = json.loads(file_path.read_text())
                users_to_add = import_data.get("users", [])
            elif file_path.suffix.lower() == '.csv':
                import csv
                users_to_add = []
                with open(file_path, 'r') as csvfile:
                    reader = csv.DictReader(csvfile)
                    for row in reader:
                        base_fields = {"email", "oauth_id", "access", "name"}
                        metadata = {
                            key: value
                            for key, value in row.items()
                            if key not in base_fields and value is not None and value.strip()
                        }
                        users_to_add.append({
                            "email": row.get("email", "").strip(),
                            "oauth_id": row.get("oauth_id", row.get("email", "").split("@")[0]),
                            "access": row.get("access", "developer").lower(),
                            "name": row.get("name", "").strip(),
                            "metadata": metadata
                        })
            else:
                return {"success": False, "error": "Unsupported file format. Use .json or .csv"}
            
            for user_data in users_to_add:
                email = (user_data.get("email") or "").strip()
                if not email:
                    failed_users.append({"error": "Missing email", "data": user_data})
                    continue

                oauth_value = (user_data.get("oauth_id") or email.split("@")[0]).strip()
                access_value = (user_data.get("access") or "developer").lower()

                raw_name = user_data.get("name")
                if isinstance(raw_name, str):
                    cleaned_name = raw_name.strip()
                    name_value: Optional[str] = cleaned_name or None
                elif raw_name is None:
                    name_value = None
                else:
                    name_value = str(raw_name).strip() or None

                metadata_value = user_data.get("metadata")
                if isinstance(metadata_value, dict):
                    metadata_value = _clean_metadata(metadata_value)
                elif metadata_value is None:
                    base_fields = {"email", "oauth_id", "access", "name", "metadata", "company"}
                    inferred = {
                        key: value
                        for key, value in user_data.items()
                        if key not in base_fields and value is not None and str(value).strip()
                    }
                    metadata_value = _clean_metadata(inferred)
                else:
                    metadata_value = None

                combined_metadata = None
                if default_meta_clean:
                    combined_metadata = dict(default_meta_clean)
                if metadata_value:
                    combined_metadata = combined_metadata or {}
                    combined_metadata.update(metadata_value)

                row_company = user_data.get("company")
                if isinstance(row_company, str):
                    row_company = row_company.strip() or None
                elif row_company is not None:
                    row_company = str(row_company).strip() or None

                target_company = company or row_company

                row_provider = user_data.get("provider")
                try:
                    normalized_provider = self._normalize_provider(
                        row_provider or normalized_default_provider
                    )
                except ValueError as exc:
                    failed_users.append({"email": email, "error": str(exc)})
                    continue

                add_result = self.add_user(
                    email=email,
                    oauth_id=oauth_value,
                    access=access_value,
                    company=target_company,
                    name=name_value,
                    metadata=combined_metadata,
                    update_existing=True,
                    provider=normalized_provider,
                )
                
                if add_result["success"]:
                    if add_result.get("updated"):
                        updated_users.append(add_result["user"])
                    else:
                        added_users.append(add_result["user"])
                else:
                    failed_users.append({"email": email, "error": add_result["error"]})
                    
        except Exception as e:
            return {"success": False, "error": f"Failed to process file: {e}"}
        
        return {
            "success": True,
            "added": len(added_users),
            "updated": len(updated_users),
            "failed": len(failed_users),
            "skipped": len(skipped_users),
            "details": {
                "added": added_users,
                "updated": updated_users,
                "failed": failed_users,
                "skipped": skipped_users,
            },
        }
    
    def get_user_activity(self, email: str, company: str) -> Dict[str, any]:
        """Get user activity from GitLab."""
        users_data = self._load_users()
        user = self._find_user(users_data, email)
        
        if not user:
            return {"success": False, "error": f"User {email} not found"}
        
        if not company:
            return {"success": False, "error": "Company parameter required for activity lookup"}
        
        # GitLab Rails command to get user activity
        gitlab_cmd = [
            f"""
            user = User.find_by(email: '{email}')
            if user
              puts JSON.generate({{
                id: user.id,
                last_sign_in_at: user.last_sign_in_at&.iso8601,
                sign_in_count: user.sign_in_count,
                created_at: user.created_at&.iso8601,
                current_sign_in_at: user.current_sign_in_at&.iso8601,
                projects_count: user.projects.count,
                groups_count: user.groups.count
              }})
            else
              puts 'null'
            end
            """
        ]
        
        result = self._execute_gitlab_command(company, gitlab_cmd)
        if not result["success"]:
            return result
        
        try:
            activity_data = json.loads(result["output"].strip())
            return {"success": True, "activity": activity_data}
        except json.JSONDecodeError:
            return {"success": False, "error": "Invalid response from GitLab"}
    
    def assign_user_to_projects(self, email: str, company: str, project_names: List[str], access_level: str = "developer") -> Dict[str, any]:
        """Assign user to specific projects within a company VM."""
        users_data = self._load_users()
        user = self._find_user(users_data, email)
        
        if not user:
            return {"success": False, "error": f"User {email} not found"}
        
        # Map access levels to GitLab access levels
        gitlab_access_levels = {
            "guest": 10,
            "reporter": 20,
            "developer": 30,
            "maintainer": 40,
            "owner": 50
        }
        
        access_level_id = gitlab_access_levels.get(access_level.lower(), 30)
        results = {"success": True, "assigned": [], "failed": []}
        
        for project_name in project_names:
            gitlab_cmd = [
                f"""
                user = User.find_by(email: '{email}')
                project = Project.find_by(name: '{project_name}') || Project.find_by(path: '{project_name}')
                
                if user && project
                  member = project.members.find_by(user: user)
                  if member
                    member.update(access_level: {access_level_id})
                    puts "Updated access for {{user.email}} in {{project.name}}"
                  else
                    project.add_developer(user, {access_level_id})
                    puts "Added {{user.email}} to {{project.name}}"
                  end
                else
                  puts "Error: User or project not found"
                end
                """
            ]
            
            result = self._execute_gitlab_command(company, gitlab_cmd)
            if result["success"] and "Error:" not in result["output"]:
                results["assigned"].append(project_name)
            else:
                results["failed"].append({"project": project_name, "error": result.get("error", "Assignment failed")})
        
        return results
    
    def get_user_permissions(self, email: str, company: str) -> Dict[str, any]:
        """Get detailed user permissions across all projects."""
        gitlab_cmd = [
            f"""
            user = User.find_by(email: '{email}')
            if user
              permissions = {{
                user: {{
                  id: user.id,
                  email: user.email,
                  name: user.name,
                  admin: user.admin?,
                  blocked: user.blocked?
                }},
                projects: [],
                groups: []
              }}
              
              # Get project memberships
              user.members.includes(:source).each do |member|
                if member.source.is_a?(Project)
                  permissions[:projects] << {{
                    id: member.source.id,
                    name: member.source.name,
                    path: member.source.path,
                    access_level: member.access_level,
                    access_level_name: member.human_access
                  }}
                end
              end
              
              # Get group memberships  
              user.group_members.includes(:source).each do |member|
                permissions[:groups] << {{
                  id: member.source.id,
                  name: member.source.name,
                  path: member.source.path,
                  access_level: member.access_level,
                  access_level_name: member.human_access
                }}
              end
              
              puts JSON.generate(permissions)
            else
              puts 'null'
            end
            """
        ]
        
        result = self._execute_gitlab_command(company, gitlab_cmd)
        if not result["success"]:
            return result
        
        try:
            permissions_data = json.loads(result["output"].strip())
            return {"success": True, "permissions": permissions_data}
        except json.JSONDecodeError:
            return {"success": False, "error": "Invalid response from GitLab"}
    
    def sync_users_with_gitlab(self, company: str) -> Dict[str, any]:
        """Synchronize local user database with GitLab users."""
        provider_list = sorted(self.supported_providers)
        provider_array = ", ".join(f"'{p}'" for p in provider_list)

        gitlab_cmd = [
            f"""
            providers = [{provider_array}]
            users = User.all.map do |user|
              identity = user.identities.where(provider: providers).first
              {
                id: user.id,
                email: user.email,
                name: user.name,
                username: user.username,
                provider: identity&.provider,
                extern_uid: identity&.extern_uid,
                created_at: user.created_at&.iso8601,
                last_sign_in_at: user.last_sign_in_at&.iso8601,
                admin: user.admin?,
                blocked: user.blocked?
              }
            end
            puts JSON.generate(users)
            """
        ]
        
        result = self._execute_gitlab_command(company, gitlab_cmd)
        if not result["success"]:
            return result
        
        try:
            gitlab_users = json.loads(result["output"].strip())
            users_data = self._load_users()
            
            sync_results = {"success": True, "synced": 0, "added": 0, "updated": 0}
            
            for gitlab_user in gitlab_users:
                email = gitlab_user.get("email")
                if not email:
                    continue
                
                local_user = self._find_user(users_data, email)
                
                if local_user:
                    # Update existing user
                    local_user["last_sync"] = time.time()
                    local_user["gitlab_id"] = gitlab_user["id"]
                    local_user["last_sign_in"] = gitlab_user.get("last_sign_in_at")
                    if not local_user.get("provider"):
                        local_user["provider"] = gitlab_user.get("provider") or self.default_provider
                    sync_results["updated"] += 1
                else:
                    # Add new user found in GitLab
                    new_user = {
                        "email": email,
                        "oauth_id": gitlab_user.get("extern_uid", email.split("@")[0]),
                        "access": "developer",  # Default access
                        "company": company,
                        "created_at": time.time(),
                        "gitlab_id": gitlab_user["id"],
                        "last_sync": time.time(),
                        "synced_from_gitlab": True,
                        "provider": gitlab_user.get("provider") or self.default_provider
                    }
                    users_data["users"].append(new_user)
                    sync_results["added"] += 1
                
                sync_results["synced"] += 1
            
            self._save_users(users_data)
            return sync_results
            
        except json.JSONDecodeError as e:
            return {"success": False, "error": f"Invalid response from GitLab: {e}"}
    
    def export_users(self, output_file: str, company: Optional[str] = None, format: str = "json") -> Dict[str, any]:
        """Export users to file."""
        users_data = self._load_users()
        users = users_data["users"]
        
        if company:
            users = [u for u in users if u.get("company") == company]
        
        output_path = Path(output_file).expanduser()
        
        try:
            if format.lower() == "json":
                output_path.write_text(json.dumps({"users": users, "exported_at": datetime.now().isoformat()}, indent=2))
            elif format.lower() == "csv":
                import csv
                with open(output_path, 'w', newline='') as csvfile:
                    if users:
                        fieldnames = users[0].keys()
                        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                        writer.writeheader()
                        for user in users:
                            writer.writerow(user)
            else:
                return {"success": False, "error": "Unsupported format. Use 'json' or 'csv'"}
                
            return {"success": True, "file": str(output_path), "count": len(users)}
            
        except Exception as e:
            return {"success": False, "error": f"Failed to export users: {e}"}
