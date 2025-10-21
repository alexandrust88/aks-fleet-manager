#!/bin/bash
#
# Azure Fleet Manager Operational Runbooks
# For managing 300+ clusters node image updates
# Include all common operations: discovery, deployment, monitoring, troubleshooting
#

set -euo pipefail

# ===== CONFIGURATION =====

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/fleet-operations.log"

# ===== UTILITY FUNCTIONS =====

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# ===== RUNBOOK 1: CLUSTER DISCOVERY =====

runbook_discover_clusters() {
    local output_file="${1:-clusters-inventory.csv}"
    
    log_info "Starting cluster discovery..."
    log_info "Output file: $output_file"
    
    # CSV header
    echo "cluster_name,cluster_rg,subscription_id,location,environment,tier,k8s_version,node_image,update_group,last_node_update" > "$output_file"
    
    local total_clusters=0
    local processed_clusters=0
    
    # Iterate through all subscriptions
    for sub in $(az account list --query "[].id" -o tsv); do
        az account set --subscription "$sub"
        
        local sub_name=$(az account show --query "name" -o tsv)
        log_info "Processing subscription: $sub_name"
        
        # Get all AKS clusters in subscription
        az aks list --query "[].[name, resourceGroup, kubernetesVersion]" -o tsv | \
        while read -r cluster_name rg k8s_version; do
            
            ((total_clusters++))
            
            # Extract metadata
            local cluster_json=$(az aks show -g "$rg" -n "$cluster_name" -o json)
            local location=$(echo "$cluster_json" | jq -r '.location')
            local tags=$(echo "$cluster_json" | jq -r '.tags // {}')
            
            local environment=$(echo "$tags" | jq -r '.environment // "untagged"')
            local tier=$(echo "$tags" | jq -r '.tier // "standard"')
            local node_image=$(echo "$cluster_json" | jq -r '.nodeResourceGroup' | cut -d_ -f3- || echo "unknown")
            
            # Get node pool version info (latest node image)
            local node_pools=$(echo "$cluster_json" | jq -r '.agentPoolProfiles[0].nodeImageVersion // "unknown"')
            
            # Derive update group from environment/location
            local update_group="${environment}-${location}-group"
            
            echo "${cluster_name},${rg},${sub},${location},${environment},${tier},${k8s_version},${node_image},${update_group},-" >> "$output_file"
            
            ((processed_clusters++))
            
        done || true
    done
    
    log_success "Discovery complete: $processed_clusters clusters found"
    log_info "Results saved to: $output_file"
    
    # Summary stats
    local dev_count=$(grep ",dev," "$output_file" | wc -l)
    local stage_count=$(grep ",stage," "$output_file" | wc -l)
    local prod_count=$(grep ",prod," "$output_file" | wc -l)
    
    cat <<EOF
    
Cluster Summary:
  Dev:   $dev_count
  Stage: $stage_count
  Prod:  $prod_count
  Total: $((dev_count + stage_count + prod_count))
EOF
}

# ===== RUNBOOK 2: BULK LABEL CLUSTERS =====

runbook_label_clusters() {
    local inventory_file="${1:-clusters-inventory.csv}"
    
    log_info "Starting bulk cluster labeling from: $inventory_file"
    
    [[ ! -f "$inventory_file" ]] && { log_error "Inventory file not found: $inventory_file"; return 1; }
    
    local total=0
    local success=0
    
    # Skip header line
    tail -n +2 "$inventory_file" | while IFS=, read -r cluster_name rg sub location env tier k8s_ver node_img update_group last_update; do
        
        ((total++))
        
        # Validate cluster exists
        if ! az aks show -g "$rg" -n "$cluster_name" &>/dev/null; then
            log_warn "Cluster not found: $cluster_name in $rg"
            continue
        fi
        
        # Apply tags (via AKS update)
        log_info "Labeling cluster: $cluster_name (env=$env, tier=$tier)"
        
        if az aks update \
            -g "$rg" \
            -n "$cluster_name" \
            --tags "environment=$env" "tier=$tier" "fleet-managed=true" "managed-by=terraform"; then
            ((success++))
            log_success "Tagged: $cluster_name"
        else
            log_error "Failed to tag: $cluster_name"
        fi
        
    done
    
    log_success "Labeling complete: $success/$total clusters successfully tagged"
}

# ===== RUNBOOK 3: BULK JOIN TO FLEET =====

runbook_join_clusters_to_fleet() {
    local inventory_file="${1:-clusters-inventory.csv}"
    local fleet_name="${2:-fleet-eu}"
    local fleet_rg="${3:-rg-fleet-management}"
    
    log_info "Joining clusters to fleet: $fleet_name"
    
    [[ ! -f "$inventory_file" ]] && { log_error "Inventory file not found"; return 1; }
    
    local total=0
    local joined=0
    
    tail -n +2 "$inventory_file" | while IFS=, read -r cluster_name rg sub location env tier k8s_ver node_img update_group last_update; do
        
        ((total++))
        
        # Derive member name from cluster name + environment
        local member_name="${cluster_name}"
        
        log_info "[$total] Joining: $cluster_name → $fleet_name (group: $update_group)"
        
        # Get cluster resource ID
        local cluster_id="/subscriptions/${sub}/resourceGroups/${rg}/providers/Microsoft.ContainerService/managedClusters/${cluster_name}"
        
        # Join to fleet with error handling
        if az fleet member create \
            --resource-group "$fleet_rg" \
            --fleet-name "$fleet_name" \
            --name "$member_name" \
            --member-cluster-id "$cluster_id" \
            --group "$update_group" \
            2>/dev/null; then
            
            ((joined++))
            log_success "Joined: $cluster_name"
            
        else
            log_warn "Failed or already member: $cluster_name"
        fi
        
        # Rate limiting to avoid throttling
        sleep 1
        
    done
    
    log_success "Fleet join complete: $joined/$total clusters"
}

# ===== RUNBOOK 4: CONFIGURE MAINTENANCE WINDOWS =====

runbook_configure_maintenance() {
    local inventory_file="${1:-clusters-inventory.csv}"
    
    log_info "Configuring maintenance windows from: $inventory_file"
    
    [[ ! -f "$inventory_file" ]] && { log_error "Inventory file not found"; return 1; }
    
    tail -n +2 "$inventory_file" | while IFS=, read -r cluster_name rg sub location env tier k8s_ver node_img update_group last_update; do
        
        log_info "Configuring maintenance window: $cluster_name (env=$env)"
        
        # Different maintenance windows per environment
        local day hour duration
        
        case "$env" in
            dev)
                day="Tuesday"
                hour=2
                duration=2
                ;;
            stage)
                day="Wednesday"
                hour=3
                duration=2
                ;;
            prod)
                day="Saturday"
                hour=4
                duration=2
                ;;
            *)
                log_warn "Unknown environment: $env, skipping maintenance window"
                continue
                ;;
        esac
        
        # Apply maintenance window
        if az aks maintenanceconfiguration add \
            --resource-group "$rg" \
            --cluster-name "$cluster_name" \
            --name "fleet-node-patch" \
            --schedule-type Weekly \
            --day "$day" \
            --start-hour "$hour" \
            --duration "$duration" \
            2>/dev/null; then
            
            log_success "Maintenance window configured: $cluster_name ($day $hour:00-$((hour+duration)):00 UTC)"
            
        else
            log_warn "Maintenance window already configured or error: $cluster_name"
        fi
        
    done
    
    log_success "Maintenance configuration complete"
}

# ===== RUNBOOK 5: CREATE UPDATE RUN =====

runbook_create_update_run() {
    local fleet_rg="${1:-rg-fleet-management}"
    local fleet_name="${2:-fleet-eu}"
    local strategy_name="${3:-strategy-ring-dev-stage-prod}"
    
    log_info "Creating update run for fleet: $fleet_name"
    
    local run_name="nodeimage-run-$(date +%Y%m%d-%H%M%S)"
    
    # Get strategy ID
    local strategy_id=$(az fleet updatestrategy show \
        --resource-group "$fleet_rg" \
        --fleet-name "$fleet_name" \
        --name "$strategy_name" \
        --query id -o tsv 2>/dev/null)
    
    if [[ -z "$strategy_id" ]]; then
        log_error "Strategy not found: $strategy_name"
        return 1
    fi
    
    # Create update run
    if az fleet updateruns create \
        --resource-group "$fleet_rg" \
        --fleet-name "$fleet_name" \
        --name "$run_name" \
        --update-strategy-id "$strategy_id" \
        --upgrade-type "NodeImage" \
        --node-image-selection "Consistent" \
        -o json > /tmp/update-run.json; then
        
        log_success "Update run created: $run_name"
        
        # Display details
        log_info "Update Run Details:"
        jq '.{name: .name, status: .status, upgradeType: .upgradeType}' /tmp/update-run.json
        
        echo "$run_name"
        
    else
        log_error "Failed to create update run"
        return 1
    fi
}

# ===== RUNBOOK 6: MONITOR UPDATE RUN =====

runbook_monitor_update_run() {
    local fleet_rg="${1:-rg-fleet-management}"
    local fleet_name="${2:-fleet-eu}"
    local run_name="${3}"
    local interval="${4:-30}"
    
    [[ -z "$run_name" ]] && { log_error "Usage: runbook_monitor_update_run RG FLEET RUN_NAME [INTERVAL]"; return 1; }
    
    log_info "Monitoring update run: $run_name (refresh every ${interval}s)"
    
    while true; do
        clear
        
        # Get run status
        local run_json=$(az fleet updateruns show \
            --resource-group "$fleet_rg" \
            --fleet-name "$fleet_name" \
            --name "$run_name" \
            -o json)
        
        local status=$(echo "$run_json" | jq -r '.status')
        
        log_info "Update Run: $run_name | Status: $status | Time: $(date)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Show member status
        az fleet updateruns members list \
            --resource-group "$fleet_rg" \
            --fleet-name "$fleet_name" \
            --update-run-name "$run_name" \
            --query "[].{Cluster:name, Status:status, Stage:stage, Reason:reason}" \
            -o table
        
        # Check if complete
        [[ "$status" != "Running" ]] && {
            log_success "Update run completed with status: $status"
            break
        }
        
        sleep "$interval"
    done
}

# ===== RUNBOOK 7: SKIP BLOCKED CLUSTER =====

runbook_skip_cluster() {
    local fleet_rg="${1:-rg-fleet-management}"
    local fleet_name="${2:-fleet-eu}"
    local run_name="${3}"
    local cluster_name="${4}"
    
    [[ -z "$run_name" || -z "$cluster_name" ]] && \
        { log_error "Usage: runbook_skip_cluster RG FLEET RUN_NAME CLUSTER_NAME"; return 1; }
    
    log_warn "Skipping cluster: $cluster_name from update run: $run_name"
    log_warn "This will mark the cluster as out-of-sync. Proceed? (yes/no)"
    read -r confirm
    
    [[ "$confirm" != "yes" ]] && { log_info "Skipped"; return 0; }
    
    if az fleet updateruns skip \
        --resource-group "$fleet_rg" \
        --fleet-name "$fleet_name" \
        --update-run-name "$run_name" \
        --member-name "$cluster_name"; then
        
        log_success "Skipped cluster: $cluster_name"
        
    else
        log_error "Failed to skip cluster"
        return 1
    fi
}

# ===== RUNBOOK 8: HEALTH CHECK =====

runbook_health_check() {
    local fleet_rg="${1:-rg-fleet-management}"
    local fleet_name="${2:-fleet-eu}"
    
    log_info "Performing fleet health check: $fleet_name"
    
    # Check fleet exists
    if ! az fleet show -g "$fleet_rg" -n "$fleet_name" &>/dev/null; then
        log_error "Fleet not found: $fleet_name"
        return 1
    fi
    
    log_success "Fleet exists: $fleet_name"
    
    # Count members
    local member_count=$(az fleet member list -g "$fleet_rg" --fleet-name "$fleet_name" --query "length([])" -o tsv)
    log_info "Member clusters: $member_count"
    
    # Check member statuses
    log_info "Member status overview:"
    az fleet member list \
        -g "$fleet_rg" \
        --fleet-name "$fleet_name" \
        --query "[].{Cluster:name, Status:status}" \
        -o table
    
    # Check recent update runs
    log_info "Recent update runs:"
    az fleet updateruns list \
        -g "$fleet_rg" \
        --fleet-name "$fleet_name" \
        --query "[].{Name:name, Status:status, Created:createdTime}" \
        -o table | head -5
    
    log_success "Health check complete"
}

# ===== RUNBOOK 9: TROUBLESHOOT PENDING CLUSTER =====

runbook_troubleshoot_pending() {
    local fleet_rg="${1:-rg-fleet-management}"
    local fleet_name="${2:-fleet-eu}"
    local run_name="${3}"
    local cluster_name="${4}"
    
    [[ -z "$run_name" || -z "$cluster_name" ]] && \
        { log_error "Usage: runbook_troubleshoot_pending RG FLEET RUN_NAME CLUSTER_NAME"; return 1; }
    
    log_warn "Troubleshooting pending cluster: $cluster_name"
    
    # Get member details from update run
    log_info "Update run member status:"
    az fleet updateruns members show \
        -g "$fleet_rg" \
        --fleet-name "$fleet_name" \
        --update-run-name "$run_name" \
        --name "$cluster_name" \
        -o json | jq '.{status: .status, reason: .reason, stage: .stage}'
    
    # Check cluster maintenance window
    local cluster_rg=$(az aks list --query "[?name=='$cluster_name'].resourceGroup" -o tsv)
    
    if [[ -n "$cluster_rg" ]]; then
        log_info "Cluster maintenance windows:"
        az aks maintenanceconfiguration list \
            -g "$cluster_rg" \
            --cluster-name "$cluster_name" \
            -o table || log_warn "No maintenance windows configured"
    fi
    
    # Check if image available in region
    log_info "Checking node image availability..."
    local region=$(az aks show -g "$cluster_rg" -n "$cluster_name" --query location -o tsv)
    log_info "Cluster region: $region"
    
    # Note: Would need additional logic to fetch release tracker
    log_info "Check AKS Release Tracker: https://releases.aks.azure.com/"
    
    log_info "Possible solutions:"
    echo "  1. Wait for maintenance window to open (check above)"
    echo "  2. Check image availability in $region on release tracker"
    echo "  3. Use 'runbook_skip_cluster' if cluster needs manual update"
}

# ===== RUNBOOK 10: GENERATE REPORT =====

runbook_generate_report() {
    local fleet_rg="${1:-rg-fleet-management}"
    local output_file="${2:-fleet-report-$(date +%Y%m%d).md}"
    
    log_info "Generating fleet report: $output_file"
    
    cat > "$output_file" <<'EOF'
# Azure Fleet Manager Report
EOF
    
    echo "Generated: $(date)" >> "$output_file"
    echo "" >> "$output_file"
    
    # Fleet inventory
    echo "## Fleet Inventory" >> "$output_file"
    az fleet list \
        --query "[].[name, location]" \
        -o table | tee -a "$output_file"
    
    echo "" >> "$output_file"
    echo "## Update Runs (Last 10)" >> "$output_file"
    
    for fleet in $(az fleet list -g "$fleet_rg" --query "[].name" -o tsv); do
        echo "### Fleet: $fleet" >> "$output_file"
        az fleet updateruns list \
            -g "$fleet_rg" \
            --fleet-name "$fleet" \
            --query "[limit(10, [])].[name, status, createdTime]" \
            -o table | tee -a "$output_file"
        echo "" >> "$output_file"
    done
    
    log_success "Report generated: $output_file"
}

# ===== MAIN MENU =====

show_menu() {
    cat <<EOF

${BLUE}Azure Fleet Manager Operations${NC}
================================

  1. Discover clusters from all subscriptions
  2. Label clusters with tags
  3. Join clusters to fleet
  4. Configure maintenance windows
  5. Create update run
  6. Monitor update run
  7. Skip blocked cluster
  8. Fleet health check
  9. Troubleshoot pending cluster
 10. Generate report
  
  0. Exit

EOF
}

# ===== MAIN EXECUTION =====

main() {
    log_info "Fleet Manager Operations Started"
    
    while true; do
        show_menu
        read -p "Select operation: " choice
        
        case "$choice" in
            1) runbook_discover_clusters ;;
            2) runbook_label_clusters ;;
            3) runbook_join_clusters_to_fleet ;;
            4) runbook_configure_maintenance ;;
            5) runbook_create_update_run ;;
            6) runbook_monitor_update_run ;;
            7) runbook_skip_cluster ;;
            8) runbook_health_check ;;
            9) runbook_troubleshoot_pending ;;
            10) runbook_generate_report ;;
            0) log_info "Exiting..."; exit 0 ;;
            *) log_error "Invalid choice" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
