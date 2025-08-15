provider "azurerm" {
  features {}
}

#############################
# Resource Group
#############################
resource "azurerm_resource_group" "rg" {
  name     = "rg-winrm-demo"
  location = "East US"
}

#############################
# Virtual Network & Subnet
#############################
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-winrm-demo"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-winrm-demo"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

#############################
# Network Security Group
#############################
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-winrm-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Allow WinRM HTTPS (5986)
resource "azurerm_network_security_rule" "winrm_https" {
  name                        = "Allow-WinRM-HTTPS"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5986"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

#############################
# Public IP
#############################
resource "azurerm_public_ip" "vm_public_ip" {
  name                = "vm-winrm-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Standard"
}


#############################
# Network Interface
#############################
resource "azurerm_network_interface" "nic" {
  name                = "nic-winrm-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

#############################
# Windows Virtual Machine
#############################
resource "azurerm_windows_virtual_machine" "vm" {
  name                  = "vm-winrm-demo"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B2ms"
  admin_username        = "azureuser"
  admin_password        = "P@ssw0rd1234!"
  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

#############################
# Enable WinRM HTTPS via Custom Script Extension
#############################
resource "azurerm_virtual_machine_extension" "enable_winrm_https" {
  name                 = "enable-winrm-https"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = <<EOT
powershell -ExecutionPolicy Unrestricted -Command "
# Create a self-signed certificate for WinRM
$cert = New-SelfSignedCertificate -DnsName $(hostname) -CertStoreLocation Cert:\\LocalMachine\\My

# Configure WinRM listener for HTTPS
winrm create winrm/config/Listener?Address=*+Transport=HTTPS @{Hostname='$(hostname)'; CertificateThumbprint=$cert.Thumbprint}

# Enable the service and PS remoting securely
winrm set winrm/config/service @{AllowUnencrypted='false'}
winrm set winrm/config/service/auth @{Basic='false'}
Enable-PSRemoting -Force
"
EOT
  })
}

#############################
# Terraform Outputs for Ansible
#############################
output "winvm_public_ip" {
  value = azurerm_public_ip.vm_public_ip.ip_address
}

output "ansible_inventory" {
  value = <<EOT
[windows]
winvm ansible_host=${azurerm_public_ip.vm_public_ip.ip_address} ansible_user=azureuser ansible_password=P@ssw0rd1234! ansible_port=5986 ansible_connection=winrm ansible_winrm_transport=ssl ansible_winrm_server_cert_validation=ignore
EOT
}
