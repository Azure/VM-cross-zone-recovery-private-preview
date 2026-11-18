# Zone resilience for Azure VMs (Preview)

**Zone resilience for Azure VMs is now in public preview.** For current requirements and step-by-step instructions, see [Zone resilience for Azure VMs on Microsoft Learn](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience).

This repository contains scripts and templates from the private preview. For the public preview, use the Microsoft Learn guide instead of the earlier private-preview registration, VM tag, script, and API instructions.

> [!IMPORTANT]
> Zone resilience for Azure VMs is in preview. Use this preview only for evaluation and testing with nonproduction VMs. Don't use it for production VMs. For more information, see [Supplemental Terms of Use for Microsoft Azure Previews](https://azure.microsoft.com/support/legal/preview-supplemental-terms/).

## Overview

Zone resilience lets you initiate failover of an eligible zonal Azure virtual machine (VM) to another availability zone in the same region. It changes the zone placement of the existing VM without creating a replacement, preserving its resource ID, VM ID, attached network interface and IP configuration, supported zone-redundant storage (ZRS) managed disks, and other supported resource settings.

ZRS synchronously replicates managed disk data across availability zones, providing a near-zero recovery point objective (RPO) for data committed to supported ZRS disks. Active requests, in-memory data, and runtime state aren't preserved.

Failover is customer-initiated and interrupts the workload while the VM is deallocated and started in the target zone. The target zone must support the VM size and have sufficient capacity. For high availability across zones, [deploy multiple VMs across availability zones](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-high-availability#deploy-vms-and-disks-across-three-availability-zones) and distribute traffic between them.

## Get started with the public preview

1. Review the current [requirements](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#requirements) and [limitations](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#limitations).
2. [Prepare an eligible nonproduction VM](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#prepare-a-vm-for-zone-failover). The OS disk and every attached data disk must use Premium SSD ZRS or Standard SSD ZRS. If used, public IP addresses must be zone-redundant Standard SKU, and load balancers or supported gateways must meet the documented network requirements.
3. [Enable zone resilience](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#enable-zone-movement) while the source zone is healthy. You can enable it when creating a VM or on an eligible existing zonal VM. Deallocate an existing VM before enabling it, then start the VM after the update succeeds.
4. Follow the documented procedure to [fail over a VM to another zone](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#fail-over-a-vm-to-another-zone).
5. [Verify the VM and workload](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#verify-failover-succeeded) before restoring traffic. If needed, follow the [troubleshooting guidance](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#troubleshoot-failover).

The public preview supports the Azure portal, Azure CLI version **2.87.0 or later**, Azure PowerShell with zone movement and force deallocation support, and Compute REST API version **`2026-03-01`**. The guide also includes Bicep examples. Use its tool-specific instructions rather than the scripts in this repository.

## Key limitations

- Failover is limited to another availability zone in the same region. It doesn't protect against regional outages or outages that affect multiple zones.
- Failover can fail if the target zone has insufficient capacity for the VM size.
- Locally redundant storage (LRS) disks, ephemeral OS disks, Premium SSD v2, Ultra Disks, Standard HDD managed disks, and data disks with write acceleration aren't supported.
- VM scale sets, availability set VMs, and Spot VMs aren't supported.
- Azure Site Recovery, on-demand capacity reservations, dedicated hosts, and proximity placement groups aren't supported for VMs with zone resilience enabled.
- The feature doesn't provide automatic failover, application-level consistency, traffic failover, recovery plans, or failback orchestration.

See the [full limitations](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#limitations) before enabling the feature.

## Disable zone resilience

Follow [Disable zone resilience](https://learn.microsoft.com/en-us/azure/virtual-machines/zone-resilience#disable-zone-movement) in the public-preview guide. Deallocate the VM before disabling zone movement, wait for the update to succeed, and then start the VM. Deallocation interrupts the workload.

## Provide feedback

Share your evaluation experience through the [preview feedback form](https://aka.ms/ZRVMPreviewFeedbackForm).

[Microsoft Privacy Statement](https://privacy.microsoft.com/en-us/privacystatement)
