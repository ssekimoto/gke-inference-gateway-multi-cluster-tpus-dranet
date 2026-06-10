<walkthrough-metadata>
  <meta name="title" content="GKE Multi-Cluster Inference Gateway with TPUs and DRANET" />
  <meta name="description" content="TPU、Cloud Storage FUSE、マネージド DRANET を使用して、マルチクラスタ GKE Inference Gateway を構築するハンズオン" />
  <meta name="component_id" content="103" />
</walkthrough-metadata>

<walkthrough-disable-features toc></walkthrough-disable-features>

# GKE Inference Gateway マルチクラスタ TPU 編

このハンズオンでは、TPU v6e、Cloud Storage FUSE、GKE マネージド DRANET、マルチクラスタ GKE Inference Gateway を使い、2 リージョン構成の Qwen 推論基盤を構築します。

参考元: [TPU、Cloud Storage FUSE、マネージド DRANET を使用してマルチクラスタ GKE Inference Gateway を構築する](https://codelabs.developers.google.com/codelabs/gke-inference-gateway-multi-cluster-tpus-dranet?hl=ja)

元コンテンツは Google Codelabs の記載に従い、ドキュメント本文は Creative Commons Attribution 4.0、コードサンプルは Apache 2.0 License の条件で扱います。

## Google Cloud プロジェクトの設定、確認

### **1. 対象の Google Cloud プロジェクトを設定**

```bash
export PROJECT_ID=$(gcloud config get-value project)
echo $PROJECT_ID
```

必要に応じて、操作対象のプロジェクトを明示します。

```bash
gcloud config set project $PROJECT_ID
```

このラボでは TPU v6e の割り当てが必要です。既定では `europe-west4-a` と `asia-northeast1-b` に Spot VM の `ct6e-standard-1t` TPU ノードを 2 台ずつ作成します。1 Pod あたり v6e 1 チップを使い、各リージョン 2 Pod、全体で 4 チップを使う想定です。割り当てが別ゾーンにある場合は、`lab-01/variables.tf` の `regions` と `region_to_tpu_zone` を更新してください。

利用モデルは `Qwen/Qwen3-8B` です。Hugging Face 上でゲートされていない公開モデルのため、このハンズオンでは Hugging Face アクセストークンを使いません。vLLM の TPU 対応表で `Qwen/Qwen3-8B` は TPU 対応済みとして掲載されています。

### **2. 必要なツールと認証**

Cloud Shell で実行する想定です。ローカル端末で実行する場合は、`gcloud`、`kubectl`、`terraform`、`helm`、`jq` が使える状態にしてください。

```bash
gcloud auth login
gcloud auth application-default login
```

教材のルートディレクトリを環境変数に入れます。以降の手順は、この `LAB_DIR` を使って移動します。

```bash
export LAB_DIR="$(pwd)"
```

## **Lab01. Terraform で VPC、GKE、Fleet を作成する**

<walkthrough-tutorial-duration duration=40></walkthrough-tutorial-duration>

このラボでは、カスタム VPC、Cloud NAT、Cloud Storage バケット、2 つの GKE Standard クラスタ、TPU v6e 1 チップノードのノードプール、Fleet 登録、マルチクラスタ サービス関連機能を作成します。

### **1. Terraform 変数を生成する**

```bash
cd "$LAB_DIR/lab-01"
envsubst < terraform.tfvars.template > terraform.tfvars
```

生成された `terraform.tfvars` に現在のプロジェクト ID が入っていることを確認します。

```bash
cat terraform.tfvars
```

### **2. ネットワーク、バケット、GKE クラスタを作成する**

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

クラスタと TPU ノードプールの作成には 10〜15 分ほどかかることがあります。各リージョンに `ct6e-standard-1t` ノードを 2 台作るため、リージョンあたり 2 チップ、全体で 4 チップを消費します。

### **3. 作成結果を確認する**

```bash
./verify-infra.sh
```

以下が確認できれば成功です。

- `gke-europe-west4` と `gke-asia-northeast1` クラスタ
- `tpu-gke-dranet-vpc` VPC
- `tpu-gke-dranet-nat-*` Cloud NAT
- `qwen-gateway-ip-*` の内部 IP
- `${PROJECT_ID}-qwen-weights` Cloud Storage バケット
- `gcs-fuse-sa` サービスアカウント

### **4. Fleet 登録を確認する**

```bash
gcloud container fleet memberships list --project=$PROJECT_ID
```

`gke-europe-west4` と `gke-asia-northeast1` が表示されれば、マルチクラスタ構成の土台が整っています。

## **Lab02. モデルの重みをキャッシュし、vLLM ワークロードをデプロイする**

<walkthrough-tutorial-duration duration=45></walkthrough-tutorial-duration>

このラボでは、`Qwen/Qwen3-8B` のモデル重みを Cloud Storage FUSE 経由でキャッシュし、両方の GKE クラスタに TPU 対応の vLLM ワークロードをデプロイします。

### **1. Kubernetes コンテキストを設定する**

```bash
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"
```

`Qwen/Qwen3-8B` はゲートされていないため、Hugging Face トークンの設定は不要です。ただし、多人数ラボでは Hugging Face の匿名ダウンロードが遅くなることがあります。講師側で公開 Cloud Storage ミラーを用意している場合は、その GCS URI を指定してください。
Terraform は各リージョンに Cloud NAT を作成するため、ノードに外部 IP がない環境でも `pip`、Hugging Face fallback、公開 Cloud Storage ミラーへの egress が利用できます。

### **2. モデル取得元を指定する**

```bash
cd "$LAB_DIR/lab-02"

# 推奨: 公開 GCS ミラーからコピーする場合
export SOURCE_MODEL_GCS_URI="gs://YOUR_PUBLIC_BUCKET/qwen3-8b"

# SOURCE_MODEL_GCS_URI を未設定にすると、Hugging Face から匿名ダウンロードします。
```

### **3. モデル重みを Cloud Storage バケットに保存する**

```bash
./cache-model.sh
kubectl logs -f job/model-downloader --context=$CTX_ASIA --pod-running-timeout=10m
```

`cache-model.sh` は両クラスタの kubeconfig を取得したうえで、Kubernetes ServiceAccount を両クラスタに作成し、モデルのダウンロード Job は Asia クラスタで実行します。
`SOURCE_MODEL_GCS_URI` が設定されている場合、Job は公開 GCS ミラーから `${PROJECT_ID}-qwen-weights` バケットへ直接コピーします。未設定の場合のみ Hugging Face から匿名ダウンロードしたあと、同じバケットへアップロードします。

進捗を別タブで確認する場合は、ラボ用 GCS バケットを直接見ます。

```bash
gcloud storage ls "gs://${PROJECT_ID}-qwen-weights/model-00005-of-00005.safetensors"
gcloud storage du "gs://${PROJECT_ID}-qwen-weights" --summarize
kubectl get job model-downloader --context=$CTX_ASIA -o wide
```

`Download complete!` と表示されたら、`Ctrl+C` でログ表示を終了します。

### **4. vLLM ワークロードを両クラスタにデプロイする**

```bash
envsubst '${PROJECT_ID}' < workload_template.yaml > workload.yaml
./deploy-workload.sh
```

ロールアウトを確認します。

```bash
for CTX in $CTX_EU $CTX_ASIA; do
  kubectl rollout status deployment/vllm-qwen --timeout=15m --context=$CTX
done
```

TPU ファブリック用のネットワークインターフェースが割り当てられていることを確認します。

```bash
for CTX in $CTX_EU $CTX_ASIA; do
  echo "Checking DRA network interfaces on $CTX..."
  kubectl --context=$CTX exec deployment/vllm-qwen -c vllm-tpu -- ls /sys/class/net
done
```

### **5. Inference API リソースを作成する**

```bash
./configure-inference-api.sh
```

`InferenceObjective`、`AutoscalingMetric`、`InferencePool` が作成され、`qwen-pool` が両クラスタからエクスポートされます。

この時点で、各リージョンに `vllm-qwen` Pod が 2 つずつ起動します。各 Pod は v6e 1 チップだけを要求します。

## **Lab03. Gateway を構成し、フェイルオーバーをテストする**

<walkthrough-tutorial-duration duration=30></walkthrough-tutorial-duration>

このラボでは、マルチクラスタ GKE Inference Gateway を作成し、Asia リージョン停止を模擬して EU 側へ推論リクエストがフェイルオーバーすることを確認します。

### **1. Cross-Regional Gateway を作成する**

```bash
cd "$LAB_DIR/lab-03"
./configure-gateway.sh
```

Gateway のプログラム完了まで 5〜10 分ほどかかることがあります。

### **2. Gateway の状態を確認する**

```bash
kubectl get gateway cross-region-gateway --context=$CTX_ASIA
kubectl get httproute qwen-route --context=$CTX_ASIA
```

### **3. フェイルオーバーをテストする**

```bash
./failover-test.sh
```

スクリプトでは、次の流れを自動実行します。

- 両クラスタの Pod 状態を確認
- Asia クラスタにテストクライアント Pod を作成
- Gateway 経由で通常の推論リクエストを実行
- Asia 側の `vllm-qwen` を `replicas=0` に変更
- Gateway ヘルスチェックの更新を待機
- 同じ Gateway IP に対する推論リクエストが EU 側へ流れることを確認
- Asia 側の `vllm-qwen` を復旧

### **4. クリーンアップ**

不要な費用が発生しないように、検証後はリソースを削除してください。

まず Kubernetes ワークロードと Gateway 関連リソースを削除します。

```bash
./cleanup-workloads.sh
```

次に Terraform で作成した基盤を削除します。

```bash
cd "$LAB_DIR/lab-01"
../lab-03/cleanup-tf.sh
```

削除時に一時的な GCP リソースロックで失敗した場合は、少し待ってから `../lab-03/cleanup-tf.sh` を再実行してください。

## **完了**

これで、TPU v6e、Cloud Storage FUSE、マネージド DRANET、GKE Inference Gateway を組み合わせた、復元力のあるマルチクラスタ推論基盤を構築できました。
