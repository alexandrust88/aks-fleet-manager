# frontdoor_update.tf
# This file provides a mechanism to update Front Door origins with real service IPs

# Create a null resource to update Front Door origins
resource "null_resource" "update_frontdoor_origins" {
  depends_on = [
    kubernetes_service.dev_service_eastus,
    kubernetes_service.dev_service_westeu,
    kubernetes_service.prod_service_eastus,
    kubernetes_service.prod_service_westeu,
    azurerm_cdn_frontdoor_origin.dev_eastus_origin,
    azurerm_cdn_frontdoor_origin.dev_westeu_origin,
    azurerm_cdn_frontdoor_origin.prod_eastus_origin,
    azurerm_cdn_frontdoor_origin.prod_westeu_origin
  ]

  # Use local-exec with a more comprehensive approach
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<EOT
      # Resource group name
      $resourceGroup = "${azurerm_resource_group.fleet_rg.name}"
      Write-Host "Resource Group: $resourceGroup"

      # Front Door profile name
      $profileName = "${azurerm_cdn_frontdoor_profile.afd_profile.name}"
      Write-Host "Front Door Profile Name: $profileName"

      # Get service IPs directly from terraform resources
      $DEV_EASTUS_IP = "${kubernetes_service.dev_service_eastus.status[0].load_balancer[0].ingress[0].ip}"
      $DEV_WESTEU_IP = "${kubernetes_service.dev_service_westeu.status[0].load_balancer[0].ingress[0].ip}"
      $PROD_EASTUS_IP = "${kubernetes_service.prod_service_eastus.status[0].load_balancer[0].ingress[0].ip}"
      $PROD_WESTEU_IP = "${kubernetes_service.prod_service_westeu.status[0].load_balancer[0].ingress[0].ip}"

      # Display the retrieved IPs
      Write-Host "Dev East US IP: $DEV_EASTUS_IP"
      Write-Host "Dev West Europe IP: $DEV_WESTEU_IP"
      Write-Host "Prod East US IP: $PROD_EASTUS_IP"
      Write-Host "Prod West Europe IP: $PROD_WESTEU_IP"

      # Verify all IPs are available
      if (-not $DEV_EASTUS_IP -or -not $DEV_WESTEU_IP -or -not $PROD_EASTUS_IP -or -not $PROD_WESTEU_IP) {
        Write-Host "One or more service IPs could not be retrieved. Exiting."
        exit 1
      }

      # Get subscription ID
      $subscriptionId = (az account show --query id -o tsv)
      Write-Host "Subscription ID: $subscriptionId"

      # Function to update and verify an origin
      function Update-Origin {
        param(
          [string]$ResourceGroup,
          [string]$ProfileName,
          [string]$OriginGroupName,
          [string]$OriginName,
          [string]$HostName
        )
        
        Write-Host "Updating $OriginName with hostname $HostName..."
        
        # First get the current origin configuration
        $origin = $(az afd origin show --origin-group-name $OriginGroupName --origin-name $OriginName --profile-name $ProfileName --resource-group $ResourceGroup)
        Write-Host "Current origin configuration: $origin"
        
        # Update the origin with a direct PUT command to ensure complete control
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Cdn/profiles/$ProfileName/originGroups/$OriginGroupName/origins/$OriginName?api-version=2021-06-01"
        
        # Create a proper JSON body with all required fields
        $body = @{
          properties = @{
            hostName = "$HostName"
            httpPort = 80
            httpsPort = 443
            priority = 1
            weight = 1000
            enabledState = "Enabled"
            originHostHeader = "$HostName"
          }
        } | ConvertTo-Json -Depth 10
        
        Write-Host "Request URI: $uri"
        Write-Host "Request body: $body"
        
        # Use PUT to replace the entire origin configuration
        $result = $(az rest --method PUT --uri $uri --headers "Content-Type=application/json" --body "$body")
        Write-Host "Update result: $result"
        
        # Give Azure some time to process the update
        Write-Host "Waiting for changes to propagate..."
        Start-Sleep -Seconds 15
        
        # Verify the update
        $updatedOrigin = $(az afd origin show --origin-group-name $OriginGroupName --origin-name $OriginName --profile-name $ProfileName --resource-group $ResourceGroup)
        Write-Host "Updated origin configuration: $updatedOrigin"
        
        return $updatedOrigin
      }
      
      # Update each origin
      $devEastResult = Update-Origin -ResourceGroup $resourceGroup -ProfileName $profileName -OriginGroupName "dev-origin-group" -OriginName "dev-eastus" -HostName "$DEV_EASTUS_IP.nip.io"
      $devWestResult = Update-Origin -ResourceGroup $resourceGroup -ProfileName $profileName -OriginGroupName "dev-origin-group" -OriginName "dev-westeu" -HostName "$DEV_WESTEU_IP.nip.io"
      $prodEastResult = Update-Origin -ResourceGroup $resourceGroup -ProfileName $profileName -OriginGroupName "prod-origin-group" -OriginName "prod-eastus" -HostName "$PROD_EASTUS_IP.nip.io"
      $prodWestResult = Update-Origin -ResourceGroup $resourceGroup -ProfileName $profileName -OriginGroupName "prod-origin-group" -OriginName "prod-westeu" -HostName "$PROD_WESTEU_IP.nip.io"

      Write-Host "Front Door origins update process completed!"
      Write-Host "Please allow 5-10 minutes for changes to fully propagate through Azure Front Door."
    EOT
  }

  # Ensure this runs whenever any service IP changes
  triggers = {
    service_ips = "${kubernetes_service.dev_service_eastus.status[0].load_balancer[0].ingress[0].ip}${kubernetes_service.dev_service_westeu.status[0].load_balancer[0].ingress[0].ip}${kubernetes_service.prod_service_eastus.status[0].load_balancer[0].ingress[0].ip}${kubernetes_service.prod_service_westeu.status[0].load_balancer[0].ingress[0].ip}"
  }
}