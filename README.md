# Terraform Task: Setup Nginx WebServer using Terraform

1) Setup ASG with nginx:latest docker running on the ASG machines
2) Setup ALB with targetgroup such that i am able to access the nginx index.html  by opening the ALB_URL

The flow of traffic is as follows

http:// ---> ASG-EC2: ---> nginx_docker:default_port
## Steps to launch server
1) terraform init
2) terraform plan -out nginx
3) terraform apply nginx

## Access the server
http://<load_balancer_dns_name>
