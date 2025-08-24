RAVE Autonomous Dev Agency — todo.md

TL;DR: Implement the core infrastructure for an autonomous software development agency by integrating GitLab, Matrix/Element, and k3s into the secure, reproducible RAVE VM, enabling external agents to be controlled via a communications plane and to test their work in sandboxed environments.

Invariants (do not change)

The RAVE VM is the product; a self-contained, secure, reproducible NixOS environment.

The primary control plane for human oversight and agent command is Matrix/Element.

The central hub for code, issues, and CI/CD is an integrated GitLab instance.

Oracles are source-of-truth; contracts & properties for core services are enforced at runtime.

Hermetic spin-up required; boot transcript must verify a fully functional "dev shop" environment.

Agents are spawned inside the VM but are controlled from outside via the Matrix plane.

Agent work is validated via sandboxed "Review App" VMs spun up from GitLab Merge Requests.

Assumptions & Scope

Assumption: Agent binaries and core logic exist in a separate repository and will be integrated, not developed, in this plan.

Assumption: A suitable NixOS module for GitLab exists and is functional (services.gitlab).

Assumption: The gitlab-runner can be configured to provision temporary VMs for review apps using the host's QEMU/KVM capabilities.

Assumption: A Matrix Application Service bridge can be developed to translate Matrix messages into systemd service commands or agent process signals.

Assumption: Thresholds if unspecified: T_mut=0.80, T_prop=0.70, SAST_high=0.

Scope (In): Implementing and integrating GitLab, Matrix/Synapse, Element, k3s, and the systemd/Matrix plumbing for agent control. Defining the "sandbox on PR" CI workflow.

Scope (Out): Development of the AI agents' core logic (PM, Developer).

Objectives

Integrate Core Services: Successfully integrate GitLab, Matrix/Synapse, and k3s into the NixOS configuration, all running as systemd services and accessible via the nginx proxy.

Establish Control Plane: Implement a Matrix-based command and control system allowing an external user to start, stop, and query the status of internal agent services.

Enable Autonomous Testing: Implement a GitLab CI/CD pipeline capable of spinning up a temporary RAVE VM clone as a "sandbox" for every merge request.

Verification: Achieve mutation ≥ 0.80 and property/metamorphic coverage ≥ 0.70 on the Matrix bridge and agent provisioning logic.

Spin-up: Achieve a one-shot hermetic boot from a clean checkout that results in a fully functional, multi-user development agency, verified by a signed boot transcript.

Risks & Mitigations

GitLab Resource Consumption: GitLab's high memory/CPU usage overwhelms the VM. → Mitigation: Enforce strict systemd MemoryMax (e.g., 8G) and CPUQuota limits; document that the full RAVE agency requires a high-resource environment.

Matrix Bridge Complexity: Bridging Matrix commands to internal systemd services is complex and insecure. → Mitigation: Use a well-defined Matrix Application Service API; treat the bridge as a security-critical component with full SAST, fuzzing, and contract testing.

CI VM-in-VM Performance: Running sandbox VMs from within the main GitLab CI runner is slow or unstable. → Mitigation: Use a dedicated, privileged GitLab Runner with direct access to the host's KVM device (/dev/kvm).

External API drift → Mitigation: Consumer/provider contracts + service virtualization for GitLab and Matrix APIs.

Env non-determinism → Mitigation: Containerized toolchain, pinned Nix lockfiles, deterministic seeds.

Unknown-unknown logic gaps → Mitigation: Metamorphic + fuzzing + runtime invariants on the agent control plane.

Method Outline (idea → mechanism → trade-offs → go/no-go )
Workstream/Variant A — Core Service Integration (P3 & P4)

Idea: Natively integrate GitLab and Matrix/Synapse into the RAVE NixOS configuration.

Mechanism: Utilize existing services.gitlab and services.matrix-synapse NixOS modules. Configure them to use the existing PostgreSQL database. Secure all secrets (initial_root_password, tokens, etc.) with sops-nix. Re-wire Grafana's OIDC to point to the internal GitLab.

Trade-offs: Significantly increases the base resource requirements of the VM. Introduces major new complex components to manage.

Go/No-Go Gate: All services (GitLab, Matrix, Grafana, PostgreSQL) are healthy after a hermetic spin-up. OIDC login from Grafana to GitLab succeeds.

Workstream/Variant B — Agent Control Plane (P5)

Idea: Create a secure bridge for external Matrix commands to control internal agent processes.

Mechanism: Develop a Matrix Application Service (Appservice) in Python/Go. This service registers with Synapse and listens for specific commands in a control room (e.g., !start-agent pm). It translates these commands into systemctl start rave-pm-agent.service calls. Agent responses are posted back to the room.

Trade-offs: Custom service to build and maintain. Becomes a critical security boundary.

Go/No-Go Gate: A human operator in an Element client can successfully start, stop, and query the status of all defined agent services.

Workstream/Variant C — Sandbox on PR (P6)

Idea: Automate the testing of agent-generated code in a fully isolated sandbox environment.

Mechanism: Configure services.gitlab-runner with the docker executor, but with privileged mode and volume mounts for /dev/kvm and the Nix store. The .gitlab-ci.yml review job will execute a script that uses nix build .#qemu and then launches the resulting QCOW2 image with QEMU. The script captures the guest IP/port and posts it as a comment on the merge request.

Trade-offs: High resource usage in CI. Requires a privileged runner, which has security implications that must be carefully managed.

Go/No-Go Gate: A merge request created by a test agent successfully triggers the pipeline, spins up a sandbox VM, and reports the access URL back to the MR.

Run Matrix
ID	Method/Variant	Budget	Inputs	Expected Gain	Promote if…
V1	Core Service Integration	High-resource VM (≥12G RAM)	NixOS Modules	Self-contained dev hub	All services pass health checks post-spinup; OIDC loop works.
V2	Agent Control Plane	Separate verification budget	Matrix Appservice API	External agent control	Control commands succeed; Mutation ≥ 0.80 on bridge logic.
V3	Sandbox on PR	High CI runner budget	.gitlab-ci.yml, QEMU	Fully automated testing	Sandbox VM boots and passes smoke tests; URL posted to MR.
V4	Runtime Invariant Monitoring	Staging/shadow only	Shadow Matrix traffic	Prod-parity signals	0 invariant breaks over N=1k control commands.
Implementation Notes

APIs/Attach points: Matrix Appservice API (/_matrix/app/v1/transactions/{txnId}), GitLab internal API (/api/v4), systemd D-Bus interface for agent service control.

Precision/Quantization: Not applicable for this infrastructure project.

Caching/State: GitLab will manage git data and artifacts. Matrix will manage chat history. Nix builds are heavily cached.

Telemetry: Log GitLab, Matrix, and agent service resource usage (CPU/Mem) via Prometheus. Track CI job durations and sandbox spin-up times.

Repro: Pin flake.lock to a specific nixpkgs revision. Record GitLab and Matrix database schema versions in the boot transcript.

Acceptance Gates

Spin-up: Clean checkout → nix build .#rave-agency → run script → GitLab, Matrix, Grafana, k3s are healthy → test user can log into all UIs via GitLab OIDC → PM agent can be started via Matrix command → boot transcript signed.

Static: 0 high/critical SAST on Matrix bridge code; typecheck clean; license policy OK.

Dynamic: Mutation ≥ 0.80 on Matrix bridge; property/metamorphic coverage ≥ 0.70 on agent command parser.

Contracts: GitLab and Matrix API clients pass contract tests against their respective services.

CI/CD Gate: A test MR must successfully build, launch a sandbox VM, and have its URL posted as a comment within a 20-minute timeout.

Domain KPI: An end-to-end "hello world" project can be initiated via Matrix and completed by placeholder agents, resulting in a merged MR, within 30 minutes.

“Make-sure-you” Checklist

Pin flake.lock and record the full Nix environment manifest.

Generate API contracts for the Matrix bridge; commit artifacts.

Save boot transcript including service health checks and OIDC login success.

Record seeds; rerun flaky tests 100×; fail on flakiness < 1%.

Quarantine network during initial spin-up to ensure self-contained operation.

Export metrics JSONL; persist logs/artifacts under artifacts/.

File/Layout Plan
code
Code
download
content_copy
expand_less

rave/
  nixos/
    configuration.nix       # Main NixOS config, imports others
    gitlab.nix              # GitLab service module
    matrix.nix              # Matrix-Synapse & Element module
    k3s.nix                 # k3s module for review apps
    agents.nix              # Systemd services for agents
  services/
    matrix-bridge/          # Source code for the Matrix Appservice
      src/
      tests/
  secrets/
    secrets.yaml            # sops-nix encrypted secrets
  .gitlab-ci.yml            # CI pipeline, now with sandbox-on-PR logic
  scripts/
    spinup_smoke.sh         # Hermetic boot and verification script
  artifacts/
    boot_transcript.json
Workflows (required)
code
Xml
download
content_copy
expand_less
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END
<workflows project="rave-agency" version="1.0">

  <!-- =============================== -->
  <!-- BUILDING: env, assets, guards   -->
  <!-- =============================== -->
  <workflow name="building">
    <env id="B0">
      <desc>Set up Nix environment and pin versions</desc>
      <commands>
        <cmd>nix flake lock --update-input nixpkgs</cmd>
        <cmd>nix build .#rave-agency --no-link -o rave-vm.qcow2</cmd>
        <cmd>nix flake archive --to artifacts/nix-source</cmd>
      </commands>
      <make_sure>
        <item>flake.lock is committed</item>
        <item>VM image build succeeds</item>
      </make_sure>
    </env>

    <contracts id="B2">
      <desc>Compile spec to contracts/properties for Matrix bridge</desc>
      <commands>
        <cmd>cd services/matrix-bridge &amp;&amp; make generate-contracts</cmd>
        <cmd>cd services/matrix-bridge &amp;&amp; make generate-properties</cmd>
      </commands>
      <make_sure>
        <item>API contracts and property tests are committed</item>
      </make_sure>
    </contracts>

    <static id="B3">
      <desc>Enable static/semantic guardrails on Matrix bridge</desc>
      <commands>
        <cmd>cd services/matrix-bridge &amp;&amp; make lint</cmd>
        <cmd>cd services/matrix-bridge &amp;&amp; make sast</cmd>
      </commands>
      <make_sure>
        <item>abort_on_high/critical findings</item>
      </make_sure>
    </static>

    <spinup id="B4">
      <desc>Hermetic boot of the full agency VM; produce boot transcript</desc>
      <commands>
        <cmd>./scripts/spinup_smoke.sh --image rave-vm.qcow2 --output artifacts/boot_transcript.json</cmd>
      </commands>
      <make_sure>
        <item>transcript is valid JSON and signed with image digest</item>
        <item>Smoke tests confirm GitLab, Matrix, Grafana UIs are up and OIDC login works</item>
      </make_sure>
    </spinup>
  </workflow>

  <!-- =============================== -->
  <!-- RUNNING: verification battery   -->
  <!-- =============================== -->
  <workflow name="running">
    <contracts id="R1">
      <desc>API contracts for Matrix bridge</desc>
      <commands>
        <cmd>cd services/matrix-bridge &amp;&amp; make test-contracts</cmd>
      </commands>
      <make_sure>
        <item>no contract breaks</item>
      </make_sure>
    </contracts>

    <properties id="R2">
      <desc>Property & metamorphic tests on Matrix bridge command parser</desc>
      <commands>
        <cmd>cd services/matrix-bridge &amp;&amp; make test-properties</cmd>
      </commands>
      <make_sure>
        <item>report property coverage ≥ 0.70</item>
      </make_sure>
    </properties>

    <mutation id="R4">
      <desc>Mutation testing for Matrix bridge adequacy</desc>
      <commands>
        <cmd>cd services/matrix-bridge &amp;&amp; make test-mutation</cmd>
      </commands>
      <make_sure>
        <item>mutation score ≥ 0.80</item>
      </make_sure>
    </mutation>
    
    <e2e_flow id="R7">
      <desc>End-to-end autonomous agency flow test</desc>
      <commands>
        <cmd>./scripts/run_e2e_agency_test.sh --scenario "hello-world"</cmd>
      </commands>
      <make_sure>
        <item>Test starts with a Matrix command</item>
        <item>Test ends with a successfully merged MR in the internal GitLab</item>
      </make_sure>
    </e2e_flow>

  </workflow>

  <!-- =============================== -->
  <!-- TRACKING: collect & compute     -->
  <!-- =============================== -->
  <workflow name="tracking">
    <harvest id="T1">
      <desc>Consolidate metrics/artifacts from tests</desc>
      <commands>
        <cmd>./scripts/collect_test_results.sh --dir artifacts/</cmd>
        <cmd>./scripts/summarize_metrics.py --input artifacts/metrics.jsonl</cmd>
        <cmd>hash-and-sign artifacts/boot_transcript.json</cmd>
      </commands>
      <make_sure>
        <item>All test outputs are archived</item>
      </make_sure>
    </harvest>

    <risk id="T2">
      <desc>Compute risk score based on service integration complexity</desc>
      <commands>
        <cmd>./scripts/compute_risk.py --complexity-gitlab=high --complexity-matrix=high --test-coverage=low</cmd>
      </commands>
      <make_sure>
        <item>Risk score is logged</item>
      </make_sure>
    </risk>
  </workflow>

  <!-- =============================== -->
  <!-- EVALUATING: promotion rules     -->
  <!-- =============================== -->
  <workflow name="evaluating">
    <gatekeeper id="E1">
      <desc>Apply gates and decide: AGENT_REFINE vs MANUAL_QA vs PROMOTE</desc>
      <commands>
        <cmd>./scripts/gatekeeper.py --transcript artifacts/boot_transcript.json --metrics artifacts/metrics_summary.json</cmd>
      </commands>
      <make_sure>
        <item>Decision is logged and CI is failed/passed accordingly</item>
      </make_sure>
    </gatekeeper>
  </workflow>

  <!-- =============================== -->
  <!-- REFINEMENT: next iteration      -->
  <!-- =============================== -->
  <workflow name="refinement">
    <agent_refine id="N1">
      <desc>Create actionable prompt from failures (e.g., failed service config)</desc>
      <commands>
        <cmd>./scripts/generate_refinement_prompt.py --failures artifacts/failures.json</cmd>
      </commands>
      <make_sure>
        <item>Prompt is logged for the next agent run</item>
      </make_sure>
    </agent_refine>

    <manual_qa id="N2">
      <desc>Human exploration handoff for complex integration failures</desc>
      <commands>
        <cmd>./scripts/create_qa_ticket.sh --transcript artifacts/boot_transcript.json</cmd>
      </commands>
      <make_sure>
        <item>Link to QA ticket is posted to the MR/commit</item>
      </make_sure>
    </manual_qa>
  </workflow>

</workflows>
Minimal Pseudocode (optional)
code
Python
download
content_copy
expand_less
IGNORE_WHEN_COPYING_START
IGNORE_WHEN_COPYING_END
# Matrix Bridge Command Handler
def handle_matrix_command(room_id, sender, command_text):
    # !start-agent pm --project="new-app"
    command, args = parse_command(command_text)
    
    if not is_sender_admin(sender):
        return post_to_matrix(room_id, "Error: Unauthorized")
    
    if command == "!start-agent":
        agent_type = args.get("agent_type")
        service_name = f"rave-{agent_type}-agent.service"
        
        # Check if service is already running
        if is_systemd_service_active(service_name):
            return post_to_matrix(room_id, f"Agent '{agent_type}' is already running.")
            
        # Execute command via systemd D-Bus or sudo systemctl
        exit_code, stdout, stderr = run_command(f"systemctl start {service_name}")
        
        if exit_code == 0:
            post_to_matrix(room_id, f"Successfully started agent '{agent_type}'.")
        else:
            post_to_matrix(room_id, f"Error starting agent '{agent_type}': {stderr}")
Next Actions (strict order)

Implement GitLab Service (P3): Add the services.gitlab module to nixos/configuration.nix, including runner integration, and secure all secrets with sops-nix.

Implement Matrix Service (P4): Add services.matrix-synapse and an Element web client, configured to use the internal GitLab for OIDC authentication.

Develop Matrix Bridge (P5): Create the Matrix Appservice (services/matrix-bridge/) that translates authenticated Matrix commands into systemd actions to control placeholder agent services.

Implement Sandbox-on-PR (P6): Modify .gitlab-ci.yml to add the review job that builds and launches a temporary VM using QEMU/KVM for testing merge requests.

Develop Spin-up Script: Create scripts/spinup_smoke.sh to perform a full hermetic boot and run health checks on all integrated services, producing the boot transcript.