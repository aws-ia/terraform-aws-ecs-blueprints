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
