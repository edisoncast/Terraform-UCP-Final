# Declaration of variables

variable "aws_access_key" {}

variable "aws_secret_key" {}

variable "region" {
  default = "us-east-2"
}

variable "network_address_space" {
    default = "10.0.0.0/16"
}

variable "subnet1_address_space" {
    default = "10.0.0.0/24" 
}


#Declare the providers

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

#data https://www.terraform.io/docs/providers/aws/d/ami.html

data "aws_ami" "ucp" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "root-device-type"
    values = ["ebs"]

  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "http" "mypublicipv4" {
   url = "http://ipv4.icanhazip.com"
}

#if we are creating a VPC we will need vpc, IG, subnet, route_table and route table association

#Resources

#Networking

resource "aws_vpc" "vpc" {
    cidr_block = var.network_address_space
    enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc.id  
}

resource "aws_subnet" "subnet1" {
    cidr_block = var.subnet1_address_space
    vpc_id = aws_vpc.vpc.id 
    map_public_ip_on_launch = true
    availability_zone = data.aws_availability_zones.available.names[0]
}

#Routing

resource "aws_route_table" "rt" {
  vpc_id =aws_vpc.vpc.id 

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta-subnet-1" {
    subnet_id = aws_subnet.subnet1.id
    route_table_id = aws_route_table.rt.id
}

# https://www.terraform.io/docs/providers/aws/r/security_group.html

resource "aws_key_pair" "key" {
  key_name   = "ucpkey"
  public_key = file("~/.ssh/ucp.pub")
}

resource "aws_security_group" "allow_connections" {

  name        = "Nginx demo from code"
  description = "Allow ports for nginx demo"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH connection"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mypublicipv4.body)}/32"] 
  }

  ingress {
    description = "HTTP connection"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "ip" {
  vpc = true
  instance = aws_instance.nginx.id

   tags = {
    Name = "UCP IP"
  }
}

# EC2 machine

resource "aws_instance" "nginx" {
  ami = data.aws_ami.ucp.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.subnet1.id
  key_name = aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.allow_connections.id]

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file("~/.ssh/ucp")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install nginx -y",
      "sudo service nginx start"
    ]
  }

  tags = {
    Name = "UCP machine"
  }

}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.nginx.id
  allocation_id = aws_eip.ip.id
}

#output

output "aws_instance_public_dns" {
  value = aws_instance.nginx.public_dns
}

#Terraform commands:
# terraform init
# terraform plan -out ucp.tfplan
# terraform apply "ucp.tfplan" 

# terraform show
# terraform output











