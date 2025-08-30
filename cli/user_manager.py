"""
User Manager - Handles GitLab OAuth user management within VMs
"""

import json
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class UserManager:
    """Manages users via GitLab OAuth integration."""
    
    def __init__(self):
        self.config_dir = Path.home() / ".config" / "rave"
        self.users_file = self.config_dir / "users.json"
        self.config_dir.mkdir(parents=True, exist_ok=True)
    
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
        ssh_cmd = [
            "ssh", "-i", config["keypair"], "-o", "StrictHostKeyChecking=no",
            "-p", str(ports["ssh"]), "root@localhost",
            "gitlab-rails", "runner"
        ] + command
        
        try:
            result = subprocess.run(ssh_cmd, capture_output=True, text=True, check=True)
            return {"success": True, "output": result.stdout}
        except subprocess.CalledProcessError as e:
            return {"success": False, "error": f"GitLab command failed: {e.stderr}"}
    
    def add_user(self, email: str, oauth_id: str, access: str, company: Optional[str] = None) -> Dict[str, any]:
        """Add a new user via GitLab OAuth."""
        users_data = self._load_users()
        
        # Check if user already exists
        if self._find_user(users_data, email):
            return {"success": False, "error": f"User {email} already exists"}
        
        # Validate access level
        valid_access = ["admin", "developer", "guest"]
        if access not in valid_access:
            return {"success": False, "error": f"Invalid access level. Use: {', '.join(valid_access)}"}
        
        # Create user object
        user = {
            "email": email,
            "oauth_id": oauth_id,
            "access": access,
            "company": company,
            "created_at": time.time()
        }
        
        # If company is specified, try to add user to GitLab in that VM
        if company:
            # GitLab Rails command to create user
            gitlab_cmd = [
                f"user = User.create!(email: '{email}', name: '{email.split('@')[0]}', username: '{email.split('@')[0]}', external: true, provider: 'oauth2_generic', extern_uid: '{oauth_id}')"
            ]
            
            result = self._execute_gitlab_command(company, gitlab_cmd)
            if not result["success"]:
                return result
        
        # Add to local user database
        users_data["users"].append(user)
        self._save_users(users_data)
        
        return {"success": True, "user": user}
    
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
        
        if company:
            users = [u for u in users if u.get("company") == company]
        
        return {"success": True, "users": users}
    
    def get_user(self, email: str) -> Dict[str, any]:
        """Get user details."""
        users_data = self._load_users()
        user = self._find_user(users_data, email)
        
        if not user:
            return {"success": False, "error": f"User {email} not found"}
        
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
    
    def bulk_add_users(self, users_file: str, company: Optional[str] = None) -> Dict[str, any]:
        """Add multiple users from CSV/JSON file."""
        file_path = Path(users_file).expanduser()
        if not file_path.exists():
            return {"success": False, "error": f"File not found: {file_path}"}
        
        results = {"success": True, "added": [], "failed": [], "skipped": []}
        
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
                        users_to_add.append({
                            "email": row.get("email", "").strip(),
                            "oauth_id": row.get("oauth_id", row.get("email", "").split("@")[0]),
                            "access": row.get("access", "developer").lower(),
                            "name": row.get("name", "")
                        })
            else:
                return {"success": False, "error": "Unsupported file format. Use .json or .csv"}
            
            for user_data in users_to_add:
                email = user_data.get("email")
                if not email:
                    results["failed"].append({"error": "Missing email", "data": user_data})
                    continue
                
                # Check if user already exists
                existing_user = self._find_user(self._load_users(), email)
                if existing_user:
                    results["skipped"].append({"email": email, "reason": "User already exists"})
                    continue
                
                # Add user
                add_result = self.add_user(
                    email=email,
                    oauth_id=user_data.get("oauth_id", email.split("@")[0]),
                    access=user_data.get("access", "developer"),
                    company=company
                )
                
                if add_result["success"]:
                    results["added"].append(add_result["user"])
                else:
                    results["failed"].append({"email": email, "error": add_result["error"]})
                    
        except Exception as e:
            return {"success": False, "error": f"Failed to process file: {e}"}
        
        return results
    
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
        gitlab_cmd = [
            """
            users = User.all.map do |user|
              {
                id: user.id,
                email: user.email,
                name: user.name,
                username: user.username,
                provider: user.provider,
                extern_uid: user.extern_uid,
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
                        "synced_from_gitlab": True
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


# Import after class definition to avoid circular import
from vm_manager import VMManager