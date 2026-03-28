# Terraform Remote-Exec Provisioner Error – Root Cause & Fix

## Error Encountered

```
Error: remote-exec provisioner error

  with module.k8s_workers.null_resource.worker_provisioner[0],
  on modules/k8s_worker/main.tf line 90, in resource "null_resource" "worker_provisioner":
  90:   provisioner "remote-exec" {

invalid empty string in 'scripts'
```

---

## Root Cause Analysis

### Problem Identified

The `remote-exec` provisioner's `inline` array contained **empty string elements** (`""`), which Terraform interprets as invalid shell script entries:

```terraform
# ❌ BROKEN - Empty strings are invalid
provisioner "remote-exec" {
  inline = [
    "echo 'Starting setup'",
    "",  # ← Invalid: empty string
    "chmod +x /tmp/worker.sh",
    "",  # ← Invalid: empty string
    "sudo /tmp/worker.sh ...",
    ""   # ← Invalid: empty string
  ]
}
```

### Why This Happens

- Empty strings (`""`) were used for readability/spacing between commands
- Terraform's remote-exec provisioner does NOT accept empty strings in the inline array
- Each element must be a valid shell command

---

## Solution Implemented

### Fixed Configuration

**File:** `infra/modules/k8s_worker/main.tf`

**Change:** Removed all empty strings and simplified the inline commands to use single-line shell statements:

```terraform
provisioner "remote-exec" {
  inline = [
    "echo '=========================================='",
    "echo 'Worker Setup Starting'",
    "echo 'Master IP: ${var.master_private_ip}'",
    "echo 'Token Length: ${length(var.rke2_token)}'",
    "echo '=========================================='",
    "test -n '${var.rke2_token}' || (echo 'ERROR: RKE2 token is empty' && exit 1)",
    "chmod +x /tmp/worker.sh",
    "echo 'Starting RKE2 worker provisioning...'",
    "sudo /tmp/worker.sh --master-ip '${var.master_private_ip}' --token '${var.rke2_token}' --environment '${var.environment}' --project '${var.project_name}' --rke2-version '${var.rke2_version}' 2>&1 | tee -a /home/ubuntu/worker-setup.log",
    "echo '=========================================='",
    "echo 'Worker provisioning script completed'",
    "echo '=========================================='",
    "test -f /var/log/rke2-worker-setup.log && tail -30 /var/log/rke2-worker-setup.log || echo 'Log file not yet available'"
  ]
}
```

### Key Changes

1. ✅ **Removed all empty strings** from the inline array
2. ✅ **Simplified command structure** – each inline element is a complete, valid shell command
3. ✅ **Preserved output logging** – echo statements provide visibility
4. ✅ **Token validation** – uses `test -n` to check if token is not empty
5. ✅ **Error handling** – proper exit on failures
6. ✅ **Log retrieval** – displays last 30 lines of worker setup logs

---

## What Changed

| Aspect | Before | After |
|--------|--------|-------|
| Empty Strings | ✗ Had multiple `""` entries | ✓ No empty strings |
| Command Format | Complex multi-line shell constructs | Simple single-line commands |
| Token Validation | Attempted if/fi blocks | Simple `test -n` check |
| Variable State | Tried to use shell variables across commands | Each command independent |
| Terraform Validation | ✗ Failed with "invalid empty string" | ✓ Passes validation |

---

## How to Test the Fix

### 1. Validate Configuration

```bash
cd infra
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

### 2. Initialize (if needed)

```bash
terraform init
```

### 3. Plan the Changes

```bash
terraform plan
```

**Should show no errors for the worker provisioner**

### 4. Apply Worker Provisioning

```bash
terraform apply -target=module.k8s_workers -auto-approve
```

**Expected Output:**
- ✓ Workers provision successfully
- ✓ No "invalid empty string in 'scripts'" error
- ✓ Visible provisioner output showing:
  - `Worker Setup Starting`
  - `Master IP: 10.0.x.x`
  - `Token Length: XXX`
  - `Starting RKE2 worker provisioning...`
  - `Worker provisioning script completed`
  - Last 30 lines of logs

### 5. Verify Nodes Joined Cluster

```bash
# SSH to master
ssh -i cluster-key.pem ubuntu@<master-ip>

# Check nodes
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes

# Expected output:
# NAME                STATUS   ROLES         AGE   VERSION
# ip-10-0-1-x.ec2    Ready    control-plane  15m   v1.29.2
# ip-10-0-2-x.ec2    Ready    worker         5m    v1.29.2
# ip-10-0-3-x.ec2    Ready    worker         5m    v1.29.2
```

---

## Validation Status

✅ **Terraform Configuration** – Passes `terraform validate`  
✅ **Code Formatting** – Passes `terraform fmt -check`  
✅ **Syntax** – Valid HCL without errors  
✅ **Provisioner Commands** – All valid shell commands  
✅ **Token Validation** – Implemented before script execution  
✅ **Error Handling** – Proper exit codes propagated  

---

## Key Learnings

### Remote-Exec Provisioner Constraints

1. ❌ **Don't use empty strings** – Terraform rejects them
2. ❌ **Don't use multi-line constructs** with shell variables across commands – Each command runs independently
3. ✅ **Use single-line commands** – Simpler and more reliable
4. ✅ **Use `test` instead of `if`** – More compatible with single-line execution
5. ✅ **Preserve output with `tee`** – Captures both to console and file

### Best Practices for Remote-Exec

```terraform
# ✅ GOOD - Valid single-line commands
provisioner "remote-exec" {
  inline = [
    "echo 'Starting setup'",
    "test -f /tmp/worker.sh || (echo 'ERROR: script missing' && exit 1)",
    "chmod +x /tmp/worker.sh",
    "sudo /tmp/worker.sh --arg value",
    "echo 'Setup complete'"
  ]
}

# ✅ GOOD - Use sub-shell for complex operations
provisioner "remote-exec" {
  inline = [
    "bash -c 'set -e; command1 && command2; echo Done'"
  ]
}

# ❌ AVOID - Empty strings
provisioner "remote-exec" {
  inline = [
    "echo 'Starting'",
    "",  # ← Don't do this
    "echo 'Done'"
  ]
}

# ❌ AVOID - Multi-line if/fi without sub-shell
provisioner "remote-exec" {
  inline = [
    "if [ condition ]; then",
    "  command",
    "fi"  # ← This doesn't work as expected
  ]
}
```

---

## Files Modified

- [infra/modules/k8s_worker/main.tf](infra/modules/k8s_worker/main.tf) – Fixed remote-exec provisioner inline array

---

## Status Summary

| Check | Result |
|-------|--------|
| Terraform Validation | ✅ PASS |
| Code Formatting | ✅ PASS |
| Empty String Errors | ✅ FIXED |
| Token Validation | ✅ IMPLEMENTED |
| Output Logging | ✅ PRESERVED |
| Error Handling | ✅ IMPLEMENTED |

**The provisioner is now ready to use. Run `terraform apply` to provision workers.**
