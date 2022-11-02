variable "aws_access_key" {}
variable "aws_secret_key" {}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region = "us-east-1"
  
}

# create ec2 instance
resource "aws_instance" "web_server01" {
  ami = "ami-08c40ec9ead489470"
  instance_type = "t2.micro"
  key_name = "deploy1_ssh"
  vpc_security_group_ids = [aws_security_group.web_ssh.id]
  subnet_id = aws_subnet.subnet401pub.id

  user_data = "${file("deploy.sh")}"

  tags = {
    "Name" : "Webserver001"
  }
  
}


# create ec2 instance - priv
resource "aws_instance" "web_server02" {
  ami = "ami-08c40ec9ead489470"
  instance_type = "t2.micro"
  key_name = "deploy1_ssh"
  vpc_security_group_ids = [aws_security_group.web_ssh.id]
  subnet_id = aws_subnet.subnet402priv.id

  tags = {
    "Name" = "Webserver002"
  }
}

# create vpc
resource "aws_vpc" "deploy4VPC" {
    cidr_block = "172.27.0.0/16"
    enable_dns_hostnames = "true"
  
    tags = {
      "Name" = "deploy4VPC"
    }
}

# create internet gateway
resource "aws_internet_gateway" "gw_deploy4" {
    vpc_id = aws_vpc.deploy4VPC.id
}

# create public subnet
resource "aws_subnet" "subnet401pub" {
    cidr_block = "172.27.0.0/18"
    vpc_id = aws_vpc.deploy4VPC.id
    map_public_ip_on_launch = "true"
    availability_zone = data.aws_availability_zones.available.names[0]
}

# create route table
resource "aws_route_table" "route-table-deploy4" {
    vpc_id = aws_vpc.deploy4VPC.id
  
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.gw_deploy4.id
    }
}

# create route table association
resource "aws_route_table_association" "RTD4-assoc" {
    subnet_id = aws_subnet.subnet401pub.id
    route_table_id = aws_route_table.route-table-deploy4.id
}

# create private subnet
resource "aws_subnet" "subnet402priv" {
    cidr_block = "172.27.64.0/18"
    vpc_id = aws_vpc.deploy4VPC.id
    map_public_ip_on_launch = "false"
    availability_zone = data.aws_availability_zones.available.names[0]
}

# create priv route table
resource "aws_route_table" "route-table-priv-deploy4" {
    vpc_id = aws_vpc.deploy4VPC.id

    route {
      cidr_block = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.natg-deploy4.id
    } 
}
# create priv route table assoc
resource "aws_route_table_association" "RTA-sub402-priv" {
    subnet_id = aws_subnet.subnet402priv.id
    route_table_id = aws_route_table.route-table-priv-deploy4.id
  
}

# create nat gateway
resource "aws_nat_gateway" "natg-deploy4" {
    allocation_id = aws_eip.nat-eip-deploy4.id
    subnet_id = aws_subnet.subnet402priv.id
  
}

# create elastic ip
resource "aws_eip" "nat-eip-deploy4" {
    vpc = true
  
}

# data
data "aws_availability_zones" "available" {
    state = "available"
}

output "instance_ip" {
  value = aws_instance.web_server01.public_ip
  
}
