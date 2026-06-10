# Lab04. Single-cluster Inference Gateway feature checks

This lab is optional and runs after Lab02. Use it when you want to test features that are easier to validate on a single GKE Inference Gateway before returning to the multi-cluster Gateway.

The default target is the Asia cluster:

```bash
cd "$LAB_DIR/lab-04"
export PROJECT_ID=$(gcloud config get-value project)
export SINGLE_GATEWAY_REGION=asia-northeast1
export SINGLE_GATEWAY_ZONE=asia-northeast1-b
export SINGLE_GATEWAY_CLUSTER=gke-asia-northeast1
export SINGLE_CTX="gke_${PROJECT_ID}_${SINGLE_GATEWAY_ZONE}_${SINGLE_GATEWAY_CLUSTER}"
```

## Create the single-cluster Gateway

```bash
./configure-single-gateway.sh
./test-single-gateway-features.sh
```

This creates a regional internal Gateway with `gatewayClassName: gke-l7-rilb` and routes traffic to the local `InferencePool/qwen-pool`.

## Body-Based Routing

Body-Based Routing reads the OpenAI request body and injects routing headers such as `X-Gateway-Model-Name`. Enable it when creating the single Gateway:

```bash
ENABLE_BBR=true ./configure-single-gateway.sh
EXPECT_BBR=true ./test-single-gateway-features.sh
```

With BBR enabled, `single-qwen-route` only accepts requests whose body model is `Qwen/Qwen3-8B`. A bogus model name should fail before it reaches vLLM.

## Prefix/KV cache behavior

The Inference Gateway endpoint picker can use request characteristics and backend metrics such as KV-cache usage to pick an endpoint. This lab exposes the relevant vLLM metrics and sends repeated-prefix prompts:

```bash
PREFIX_ROUNDS=8 ./test-single-gateway-features.sh
```

For regional distribution on the multi-cluster Gateway, use:

```bash
cd "$LAB_DIR/lab-03"
REQUESTS_PER_REGION=10 MAX_TOKENS=16 ./regional-distribution-test.sh
```

That script compares per-pod vLLM counters before and after Gateway traffic.

## LoRA adapter checks

LoRA requires vLLM to start with LoRA support enabled and an adapter path that is visible inside the vLLM container. The base lab does not bundle an adapter.

Redeploy vLLM with runtime LoRA support:

```bash
cd "$LAB_DIR/lab-02"
export VLLM_EXTRA_ARGS="--enable-lora --max-loras 4 --max-lora-rank 64"
export VLLM_ALLOW_RUNTIME_LORA_UPDATING=True
envsubst '${PROJECT_ID} ${VLLM_EXTRA_ARGS} ${VLLM_ALLOW_RUNTIME_LORA_UPDATING}' < workload_template.yaml > workload.yaml
./deploy-workload.sh
```

Then load an adapter from a path mounted in the vLLM container:

```bash
cd "$LAB_DIR/lab-04"
export LORA_NAME="my-qwen-lora"
export LORA_PATH="/data/lora/my-qwen-lora"
./load-lora-adapter.sh
```

If you also enable BBR, add a route match for the adapter model name or temporarily return to the default `single-qwen-route` so that adapter requests can reach vLLM.
