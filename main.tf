/* provider */

provider "aws" {
  region = "eu-west-3"
}

data "aws_vpc" "default" {
  default = true
}

# Data source for the default subnet
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

terraform {
    backend "s3" {
      bucket = "acebyte-tfstate"
      key    = "dev/terraform.tfstate"
      region = "eu-west-3"
      encrypt = true
      dynamodb_table = "terrform-lock-table"
    }
  }



resource "aws_security_group" "ec2_sg" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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



/* EC2 */

resource "aws_launch_template" "gst" {
  name_prefix   = "gst-"
  image_id           = "ami-0756283460878b818"  # Replace with the appropriate AMI ID
  instance_type = "t2.micro"

  key_name = "training" # Replace with your key pair name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "training"
  }
}


# Auto Scaling Group
resource "aws_autoscaling_group" "gst" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = data.aws_subnets.default.ids
  launch_template {
    id      = aws_launch_template.gst.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "gst-instance"
    propagate_at_launch = true
  }
}


# Load Balancer
resource "aws_lb" "gst" {
  name               = "gst-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_sg.id]
  subnets            = data.aws_subnets.default.ids
}


# Load Balancer Target Group
resource "aws_lb_target_group" "gst" {
  name     = "gst-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}

# Auto Scaling Group Attachment
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.gst.name
  lb_target_group_arn = aws_lb_target_group.gst.arn
}


# Load Balancer Listener
resource "aws_lb_listener" "gst" {
  load_balancer_arn = aws_lb.gst.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gst.arn
  }
}


## TODO
#  Test if LB is working, make some stress test
#  Add S3 to store exectuble
#  Add lambda
#  Add Step Function
#  Add RDS
#  Try to make this file modulized
#  
