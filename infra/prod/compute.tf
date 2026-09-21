# Required by azurerm_linux_virtual_machine's mandatory auth block — this
# key is never distributed or used for actual login. Real interactive
# access is via Bastion + the Azure AD login extension below, which is the
# genuine equivalent of AWS's IAM-based SSM Session Manager (no distributed
# credential). This key exists only because the resource's schema requires
# either a password or an SSH key at creation time; it satisfies that
# requirement without anyone needing to hold or use it.
resource "tls_private_key" "vm_unused" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
 
resource "azurerm_linux_virtual_machine" "prod" {
  name                            = "eai-prod-host"
  resource_group_name             = azurerm_resource_group.prod.name
  location                        = azurerm_resource_group.prod.location
  size                            = "Standard_B2s_v2"
  admin_username                  = "azureuser"
  network_interface_ids           = [azurerm_network_interface.vm.id]
  disable_password_authentication = true
 
  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.vm_unused.public_key_openssh
  }
 
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm.id]
  }
 
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
 
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
 
  # custom_data = base64encode(<<-EOF
  #   #!/bin/bash
  #   set -e
  #   apt-get update -y
  #   apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg docker.io docker-compose-plugin
  #   systemctl enable --now docker
  #   usermod -aG docker azureuser

  #   # Azure CLI is required on the VM because the deploy workflow's Run
  #   # Command script performs `az login --identity` + `az acr login`
  #   # locally on this VM, rather than assuming any pre-installed tooling.
  #   curl -sL https://aka.ms/InstallAzureCLIDeb | bash

  #   mkdir -p /opt/eai
  # EOF
  # )

  # Run this if the VM is already created and you want to bootstrap it due to /opt/eai being missing or the Azure CLI not being installed.
  # This is a one-time operation, and the script is idempotent.
  # (.venv) PS C:\enterprise-integration-azure\infra\uat>
  # az vm run-command invoke `
  #    --resource-group eai-uat-rg `
  #    --name eai-uat-host `
  #    --command-id RunShellScript `
  #    --scripts 'set -eux
  #  mkdir -p /opt/eai
  #  
  #  if ! command -v az >/dev/null 2>&1; then
  #    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  #  fi
  #  
  #  az version
  #  docker --version
  #  docker compose version
  #  ls -ld /opt/eai'
  #

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/eai-bootstrap.log) 2>&1

    # Ubuntu cloud images run unattended-upgrades and apt-daily(-upgrade)
    # timers on first boot; these race with this script's own apt-get calls
    # for /var/lib/dpkg/lock-frontend and cause a hard, non-retried failure
    # rather than a wait. Disabling them here, before any apt-get call
    # below, removes the race rather than papering over it with a retry
    # loop against an opponent of unknown duration.
    systemctl stop unattended-upgrades.service 2>/dev/null || true
    systemctl disable unattended-upgrades.service 2>/dev/null || true
    systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

    # Defense-in-depth: wait up to 120s for the lock on every invocation,
    # in case cloud-init's own bootstrap-phase apt-get is still mid-run
    # despite the disables above.
    APT="apt-get -o DPkg::Lock::Timeout=120"

    $APT update -y
    $APT install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    $APT update -y
    $APT install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker
    usermod -aG docker azureuser

    curl -sL https://aka.ms/InstallAzureCLIDeb | bash

    mkdir -p /opt/eai
  EOF
  )  
}
 
# Grants the Azure AD login extension's actual authorization — without
# this, the extension is installed but no one can use it to sign in.
resource "azurerm_role_assignment" "vm_admin_login" {
  scope                = azurerm_linux_virtual_machine.prod.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = data.azurerm_client_config.current.object_id
}
 
# Installs Azure AD authentication on the VM itself — the actual mechanism
# that makes Bastion's "Connect with Azure AD" option work, and what
# removes the need for anyone to ever touch the throwaway SSH key above.
resource "azurerm_virtual_machine_extension" "aad_login" {
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.prod.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}
 
output "vm_id"       { value = azurerm_linux_virtual_machine.prod.id }
output "vm_public_ip" { value = azurerm_public_ip.vm.ip_address }
