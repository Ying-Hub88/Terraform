# This code block sets up the:
# VNet/Subnet
# Public IP address
# Network interface
# Boot diagnostic account
# Virtual Machine

provider "azurerm" {
  features {
    
  }
}

variable "rg" {
    
} 

variable "location" {    
  #description = "This is where the resource is created."
}

variable "no" {
    
} 

variable "nsgrules" {
  
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "myterraformgroup" {
  name     = var.rg
  location = var.location
}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
  count = var.no
  name                = "myVnet-${count.index +1}"
  address_space       = ["10.${count.index +1}.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
  count = var.no
  name                 = "mySubnet-${count.index +1}"
  resource_group_name  = azurerm_resource_group.myterraformgroup.name
  virtual_network_name = element(azurerm_virtual_network.myterraformnetwork.*.name, count.index)
  address_prefixes       = ["10.${count.index +1}.0.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "myterraformpublicip" {
  count = var.no
  name                         = "myPublicIP-${count.index +1}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.myterraformgroup.name
  allocation_method            = "Dynamic"
}

# Create Network Security Group
resource "azurerm_network_security_group" "myterraformnsg" {
  name                = "myNetworkSecurityGroup"
  location            = var.location
  resource_group_name = azurerm_resource_group.myterraformgroup.name
}

# Create Network Security rules
resource "azurerm_network_security_rule" "myterraformnsgrules" {
  for_each                    = var.nsgrules 
  name                        = each.key
  direction                   = each.value.direction
  access                      = each.value.access
  priority                    = each.value.priority
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = azurerm_resource_group.myterraformgroup.name
  network_security_group_name = azurerm_network_security_group.myterraformnsg.name
}

# Create network interface
resource "azurerm_network_interface" "myterraformnic" {
  count = var.no
  name                      = "myNIC-${count.index +1}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.myterraformgroup.name

  ip_configuration {
    name                          = "myNicConfiguration"
    subnet_id                     = element(azurerm_subnet.myterraformsubnet.*.id, count.index)
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.myterraformpublicip.*.id, count.index)}"
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  count = var.no
  network_interface_id      = element(azurerm_network_interface.myterraformnic.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.myterraformgroup.name
  }
  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
  name                        = "storacc${random_id.randomId.hex}"
  resource_group_name         = azurerm_resource_group.myterraformgroup.name
  location                    = var.location
  account_tier                = "Standard"
  account_replication_type    = "LRS"
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "myterraformvm" {
  count = var.no
  name                  = "myVM-${count.index +1}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.myterraformgroup.name
  network_interface_ids = ["${element(azurerm_network_interface.myterraformnic.*.id, count.index)}"]
  size                  = "Standard_B1s"
  custom_data         = base64encode(file("./scripts/cloud-init.txt"))

  os_disk {
    name              = "myOsDisk-${count.index +1}"
    caching           = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  computer_name  = "vm-${count.index +1}"
  admin_username = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username       = "azureuser"
    public_key     = file("./.ssh/id_rsa.pub")
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
  }
}