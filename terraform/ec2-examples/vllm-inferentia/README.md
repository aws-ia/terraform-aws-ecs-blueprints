# ECS machine learning distributed training

This solution blueprint creates the infrastructure needed to run GenAI inference using [vLLM](https://docs.vllm.ai/en/latest/index.html) with [AWS Neuron](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/) and Inferentia 2 instances.  This solution is based on similar examples for running inference using vLLM on [EKS](https://aws.amazon.com/blogs/machine-learning/deploy-meta-llama-3-1-8b-on-aws-inferentia-using-amazon-eks-and-vllm/) and [EC2](https://aws.amazon.com/blogs/machine-learning/serving-llms-using-vllm-and-amazon-ec2-instances-with-aws-ai-chips/) using Inferentia-based instances.

> Insert Diagram here

By default, this blueprint deploys inf2.8xlarge instances optimized for GenAI inference workloads. The setup is tailored for running vLLM with pre-compiled Neuron-compatible models. You can modify the instance type and resource allocation by changing the variables in the Terraform configuration.

## Components

*	ECS Cluster:
    *	Uses an autoscaling group to provision inf2 instances for the ECS cluster.
    *	Allows dynamic scaling of GenAI workloads.
*	ECS Service Definition:
    *	vLLM Service: Configured to serve requests for GenAI inference using vLLM.
*	Application Load Balancer:
    *	Exposes the vLLM inference service endpoint to clients.
    *	Configured with a target group and health checks for monitoring service availability.
*	CloudWatch Logs:
    *	Logs from ECS tasks and services are collected in CloudWatch for monitoring and debugging.


## Prequequisites

### Hugging Face Account and API Key

To use the meta-llama/Llama-3.2-1B model within the blueprint, you’ll need a Hugging Face account and and an API key to access to the model. Follow these steps to set these up:

1.	[Sign up for a Hugging Face account](https://huggingface.co/join) if you don’t already have one.
2.	Go to the [meta-llama/Llama-3.2-1B model card](https://huggingface.co/meta-llama/Llama-3.2-1B) on Hugging Face.
3.	Agree to the model license to gain access.
4.	Generate your Hugging Face API key:
	*	Navigate to your [Hugging Face Account Settings](https://huggingface.co/settings/tokens).
	*	Under the Access Tokens section, click New Token.
	*	Provide a name for your token and set the role to write or read.
	* Copy the token when prompted (as shown in the following figure). The token will not be displayed again.

## Preparing the Docker Image

To run the model, you’ll need to build and push a Docker image with the required dependencies to Amazon Elastic Container Registry (Amazon ECR). While [you can use docker buildx](https://docs.docker.com/build/building/multi-platform/) to do this, if you dont have your local machine configured for this, you can use an Inf2-based EC2 instance as a build environment to build your container for the arm64 architecture.

### Steps to launch an Inf2-based Build Environment:

#### 1. Launch an Inf2-based EC2 Instance
1. Open the AWS Management Console and launch an Inf2-based EC2 instance (e.g., inf2.8xlarge). You can use a [guide like this](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-launch-instance-wizard.html). If this is your first time using inf/trn instances, you will need to [request a quota increase](https://repost.aws/articles/ARgmEMvbR6Re200FQs8rTduA/inferentia-and-trainium-service-quotas).
2. Ensure the instance has:
	  * Access to your [Amazon ECR repository](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html).
	  * Permissions for Docker and AWS CLI operations.
	  * Can be accessed via Session Manager or is [configured for SSH access](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connection-prereqs-general.html)
3.	Access the instance through Session manager or SSH into the EC2 instance using the following command:

```bash
ssh -i your-key.pem ec2-user@<ec2-public-ip>
```

#### 2. Setup Environmental Variables

```bash
export ECR_REPO_NAME=vllm-neuron
export AWS_REGION=us-west-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

#### 3. Create an ECR Repository
Run the following command to create an ECR repository:

```bash
aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
```

#### 4. Create the Dockerfile

> If you're using your local development machine, you can skip this step as a Dockerfile already exists in this project.

Create the Dockerfile for the VLLM model:
```bash
cat > Dockerfile <<EOF
# default base image
FROM public.ecr.aws/neuron/pytorch-inference-neuronx:2.1.2-neuronx-py310-sdk2.20.0-ubuntu20.04
# Clone the vllm repository
RUN git clone https://github.com/vllm-project/vllm.git
# Set the working directory
WORKDIR /vllm
RUN git checkout v0.6.0
# Set the environment variable
ENV VLLM_TARGET_DEVICE=neuron
# Install the dependencies
RUN python3 -m pip install -U -r requirements-neuron.txt
RUN python3 -m pip install .
# Modify the arg_utils.py file to support larger block_size option
RUN sed -i "/parser.add_argument('--block-size',/ {N;N;N;N;N;s/\[8, 16, 32\]/[8, 16, 32, 128, 256, 512, 1024, 2048, 4096, 8192]/}" vllm/engine/arg_utils.py
# Install ray
RUN python3 -m pip install ray
RUN pip install -U  triton>=3.0.0
# Set the entry point
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
EOF
```

#### 5. Build and Push the Docker Image

Run the following commands to build and push the Docker image:

1.	Authenticate Docker to your ECR registry:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

2. 	Build the Docker image:

```bash
docker build -t ${ECR_REPO_NAME}:latest .
```

3. Tag the image

```bash
docker tag ${ECR_REPO_NAME}:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPO_NAME}:latest
```

4. Push the image to ECR

```bash
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPO_NAME}:latest
```

5. Copy the ECR image URI for your use in the main.tf file within this project.

```bash
echo "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPO_NAME}:latest"
```

## Deployment Prerequisites

1. Modify the local variables at line 6 of `main.tf`
```nano
  name                    = "ecs-demo-vllm-inferentia"    # Defaul name of the project
  region                  = "us-west-2"                   # Default region
  instance_type           = "inf2.8xlarge"                # Default instance size
  vllm_container_image    = "<ECR IMAGE URI>"             # ECR Image URI you created when building and pushing your image
  hugging_face_api_key    = "<YOUR HUGGIN FACE API KEY>"  # Your Hugging Face API Key
```


## Deployment

1. Deploy core-infra resources

```shell
cd ./terraform/ec2-examples/core-infra
terraform init
terraform apply -target=module.vpc -target=aws_service_discovery_private_dns_namespace.this
```

2. Deploy this blueprint

```shell
cd ../vllm-inferentia
terraform init
terraform apply
```

## Example: Running GenAI Inference

Once the cluster and services are deployed, you can use the load balancer DNS name (output during the deployment) to send requests to the vLLM service.


Send a POST request to the vLLM OpenAI-compatible endpoint:
```bash
curl -X POST http://<ALB_DNS_NAME>:8000/v1/completions \
-H "Content-Type: application/json" \
-d '{
  "model": "meta-llama/Llama-3.2-1B",
  "prompt": "Write a short poem about technology",
  "max_tokens": 100,
  "temperature": 0.7
}'
```

Example Response:
```json
{
  "id": "cmpl-6ze...",
  "object": "text_completion",
  "created": 1680307267,
  "model": "meta-llama/Llama-3.2-1B",
  "choices": [
    {
      "text": "\n\nTechnology, a wondrous art,\nA force that shapes the world's heart.\nIn circuits small and data vast,\nIt links the future to the past.",
      "index": 0,
      "logprobs": null,
      "finish_reason": "stop"
    }
  ]
}
```
## What do you do next?

Congratulations on successfully deploying your vLLM inference solution on ECS with AWS Inferentia! Here are some ideas to take your implementation to the next level:

1. Explore Frontend Integrations
	* Gradio: Use [Gradio](https://www.gradio.app/) to create an interactive web interface for your model, allowing users to test various prompts and visualize responses.
	* OpenWebUI: Deploy [OpenWebUI](https://github.com/open-webui/open-webui) as an additional frontend for your model, providing a user-friendly way to interact with the OpenAI-compatible endpoint.

2. Build Custom Python Applications
	*	Create Python scripts or applications that integrate your inference service to solve real-world problems:
	*	Automate customer support chatbots.
	*	Generate summaries, translations, or other natural language tasks.
	*	Build a personalized AI assistant tailored to your organizational needs.

3. Integrate with Existing Workflows
	*	Serverless Architectures: Use AWS Lambda or Step Functions to trigger and process model inference requests in response to specific events.
	*	Data Pipelines: Integrate the model into your data pipelines for real-time predictions or insights, such as tagging or categorizing documents automatically.
	*	CRM and ERP Systems: Embed the model into your enterprise systems to provide intelligent insights or streamline processes.

4. Optimize for Performance
	*	Experiment with different batch sizes and parallelization settings in vLLM to handle more concurrent requests or improve latency.
	*	Use Neuron monitoring tools to analyze and fine-tune the utilization of Inferentia chips for maximum efficiency.

5. Scale and Extend
	*	Add multi-model support by deploying multiple versions of your model (e.g., fine-tuned for specific tasks) and routing traffic dynamically using the ALB.
	*	Experiment with autoscaling policies to dynamically adjust the number of running tasks based on request volume.

6. Learn from Amazon’s Approach
	*	Discover how Amazon’s engineering team scaled generative AI for Amazon Rufus, powering conversational shopping experiences during Prime Day.
	*	Adapt lessons learned from their implementation to improve scalability, reliability, and cost-efficiency in your use case.
## Clean up

1. Destroy this blueprint

```shell
terraform destroy
```

1. Destroy core-infra resources

```shell
cd ../core-infra
terraform destroy

```

## Troubleshooting



## Support

Please open an issue for questions or unexpected behavior
