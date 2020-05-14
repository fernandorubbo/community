# Using Istio's proxy-based telemetry with Google Cloud's operations suite and Workload Identity

This guide is for Google Kubernetes Enginer (GKE) cluster operators using
Workload Identity who want to configure Istio to report telemetry (logging,
metrics, and tracing) to Google Cloud's operations suite (formerly Stackdriver)
using Istio's proxy-based telemetry, also known as Telemetry V2.

<walkthrough-alt>

If you like, you can take the interactive version of this tutorial, which runs
in the Cloud Console:

[![Open in Cloud Console](https://walkthroughs.googleusercontent.com/tutorial/resources/open-in-console-button.svg)](https://ssh.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https%3A%2F%2Fgithub.com%2Fhalvards%2Fcommunity.git&cloudshell_git_branch=istio-proxy-telemetry-operations-suite-workload-identity&cloudshell_working_dir=tutorials%2Fistio-proxy-telemetry-operations-suite-workload-identity&cloudshell_tutorial=index.md)

</walkthrough-alt>

## Introduction

Istio 1.3 introduced
[Telemetry V2](https://istio.io/docs/reference/config/telemetry/),
which is sometimes referred to as proxy-based telemetry or Mixer-less
telemetry. When using Telemetry V2, the Envoy-based Istio sidecar proxies
report telemetry directly to the metric backends. Prior to this, a
centralized Mixer adapter reported telemetry instead.

[Google Cloud's operations suite](https://cloud.google.com/products/operations)
can be used as a backend for Istio telemetry. This means that Istio sends logs to [Cloud Logging](https://cloud.google.com/logging),
metrics to [Cloud Monitoring](https://cloud.google.com/monitoring),
and traces to [Cloud Trace](https://cloud.google.com/trace).

[Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
allows you to associate Kubernetes service accounts to Cloud Identity and
Access Management (IAM) service accounts. Enabling Workload Identity on a
Google Kubernetes Engine (GKE) cluster means that pods don't have access
to the Cloud IAM service account attached to the GKE cluster node where the
pod runs. Instead, pods running as a Kubernetes service account can act as the
associted Cloud IAM service account for authorized access to Google APIs.

Two containers in the same pod share a Kubernetes service account. This means
that the
[Envoy-based Istio sidecar proxy container](https://istio.io/docs/concepts/traffic-management/)
runs as the same Kubernetes service account as the app container in the same
pod.

This tutorial shows you how to configure Workload Identity and Cloud IAM to
give Istio permission to report telemetry to Google Cloud's operations suite
using Istio's Telemetry V2 feature.

## Objectives

-   Create a GKE cluster with the Workload Identity feature enabled.
-   Install Istio and configure it to use Google Cloud's operations suite.
-   Configure Cloud IAM to allow Istio to report telemetry to Google Cloud's
    operations suite.
-   Deploy a sample app.
-   Verify that telemetry from both Istio and the sample app appear in
    Google Cloud's operations suite.

## Costs

This tutorial uses the following billable components of Google Cloud:

-   [Google Cloud's operations suite](https://cloud.google.com/stackdriver/pricing)
-   [GKE](https://cloud.google.com/kubernetes-engine/pricing)

To generate a cost estimate based on your projected usage, use the
[pricing calculator](https://cloud.google.com/products/calculator).
New Google Cloud users might be eligible for a free trial.

When you finish this tutorial, you can avoid continued billing by deleting the
resources you created. For more information, see [Cleaning up](#cleaning-up).

## Before you begin

<walkthrough-project-billing-setup></walkthrough-project-billing-setup>

<walkthrough-alt>

1.  [Sign in](https://accounts.google.com/Login) to your Google Account.

    If you don't already have one,
    [sign up for a new account](https://accounts.google.com/SignUp).

2.  In the Cloud Console, on the project selector page, select or create a
    Google Cloud project.

    **Note:** If you don't plan to keep the resources that you create in this
    procedure, create a project instead of selecting an existing project. After
    you finish these steps, you can delete the project, removing all resources
    associated with the project.

    [Go to the project selector page](https://console.cloud.google.com/projectselector2/home/dashboard)

3.  Make sure that billing is enabled for your Google Cloud project.
    [Learn how to confirm billing is enabled for your project.](https://cloud.google.com/billing/docs/how-to/modify-project)

4.  In the Cloud Console, go to Cloud Shell.

    [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://ssh.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https%3A%2F%2Fgithub.com%2Fhalvards%2Fcommunity.git&cloudshell_git_branch=istio-proxy-telemetry-operations-suite-workload-identity&cloudshell_working_dir=tutorials%2Fistio-proxy-telemetry-operations-suite-workload-identity)

    Click **Confirm** to clone the Git repo into your Cloud Shell.

    At the bottom of the Cloud Console, a Cloud Shell session opens and
    displays a command-line prompt. Cloud Shell is a Linux shell environment
    with the Cloud SDK already installed, including the `gcloud` command-line
    tool, and with values already set for your current project. It can take a
    few seconds for the session to initialize. You use Cloud Shell to run all
    the commands in this tutorial.

</walkthrough-alt>

1.  In Cloud Shell, set the Google Cloud project you want to use for this
    tutorial:

    ```bash
    gcloud config set core/project PROJECT_ID
    ```

    where `PROJECT_ID` is your project ID.

2.  Enable the Google Cloud and GKE APIs:

    ```bash
    gcloud services enable \
        cloudapis.googleapis.com \
        container.googleapis.com
    ```

3.  Set the `gcloud` tool default Compute Engine zone:

    ```bash
    gcloud config set compute/zone us-central1-f
    ```

    This is zone where you will create the GKE cluster. If you like, you can
    [choose a different zone](https://cloud.google.com/compute/docs/regions-zones)
    for this tutorial.

## Creating the GKE cluster

1.  In Cloud Shell, create a GKE cluster and enable Workload Identity:

    ```bash
    gcloud container clusters create istio-proxy-telemetry \
        --enable-ip-alias \
        --enable-stackdriver-kubernetes \
        --machine-type e2-standard-2 \
        --num-nodes 4 \
        --workload-pool $GOOGLE_CLOUD_PROJECT.svc.id.goog
    ```

2.  Bind the `cluster-admin` Kubernetes role to your Google account using the
    `kubectl` command-line tool:

    ```bash
    kubectl create clusterrolebinding cluster-admin-binding \
        --clusterrole cluster-admin \
        --user $(gcloud config get-value core/account)
    ```

    You need this role binding to install Istio.

## Configuring Workload Identity

1.  In Cloud Shell, create a Cloud IAM service account for the Istio system
    components:

    ```bash
    gcloud iam service-accounts create istio-proxy-telemetry-system \
        --display-name "Istio proxy telemetry system service account"
    ```

2.  Bind the Cloud IAM service account you just created to the Kubernetes
    service accounts for Istio's Pilot and Ingress Gateway system components:

    ```base
    for KSA in istio-pilot-service-account istio-ingressgateway-service-account ; do
        gcloud iam service-accounts add-iam-policy-binding \
            istio-proxy-telemetry-system@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
            --member "serviceAccount:$GOOGLE_CLOUD_PROJECT.svc.id.goog[istio-system/$KSA]" \
            --role roles/iam.workloadIdentityUser
    done
    ```

    **Note:** This tutorial installs a subset of the available Istio
    components. In your own environment you may install additional components.
    If you do, you also need to create Cloud IAM policy bindings for the
    Kubernetes service accounts of the additional components.

3.  Create a Cloud IAM service account for the sample app:

    ```bash
    gcloud iam service-accounts create istio-proxy-telemetry-app \
        --display-name "Istio proxy telemetry app service account"
    ```

4.  Bind the sample app Cloud IAM service account you just created to a
    Kubernetes service account called `app` in a Kubernetes namespace called
    `demo`:

    ```base
    gcloud iam service-accounts add-iam-policy-binding \
        istio-proxy-telemetry-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
        --member "serviceAccount:$GOOGLE_CLOUD_PROJECT.svc.id.goog[demo/app]" \
        --role roles/iam.workloadIdentityUser
    ```

    You will create the Kubernetes service account and namespace later.

5.  Bind the predefined Cloud IAM roles for writing to Cloud Logging
    ([`logging.logWriter`](https://cloud.google.com/logging/docs/access-control)),
    Cloud Monitoring
    ([`monitoring.metricWriter`](https://cloud.google.com/monitoring/access-control#predefined_roles)),
    and Cloud Trace
    ([`cloudtrace.agent`](https://cloud.google.com/trace/docs/iam))
    to both of the Cloud IAM service accounts you just created:

    ```bash
    for ROLE in logging.logWriter monitoring.metricWriter cloudtrace.agent ; do
        for SA in istio-proxy-telemetry-system istio-proxy-telemetry-app ; do
            gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
                --member serviceAccount:$SA@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
                --role roles/$ROLE > /dev/null
        done
    done
    ```

## Installing Istio

1.  Define the version of Istio you will install:

    ```bash
    export ISTIO_VERSION=1.5.4
    ```

2.  Download the
    [`istioctl` command-line tool](https://istio.io/docs/setup/install/istioctl/):

    ```bash
    gsutil -m cp "gs://istio-release/releases/$ISTIO_VERSION/istioctl-$ISTIO_VERSION-linux.tar.gz" - | tar zx
    ```

3.  Inspect the Istio operator manifest you will use to install Istio. This
    manifest enables Telemetry V2 and configures Google Cloud's operations
    suite as the telemetry backends for logging, monitoring and tracing using
    the legacy `stackdriver` name:

    <walkthrough-editor-select-line
        filePath="cloudshell_open/community/tutorials/istio-proxy-telemetry-operations-suite-workload-identity/istio-operator.tmpl.yaml"
        startLine="15" startCharacterOffset="0"
        endLine="15" endCharacterOffset="0"
        text="Open istio-operator.tmpl.yaml">
    </walkthrough-editor-select-line>

    <walkthrough-alt>

    `istio-operator.tmpl.yaml`:

    [embedmd]:# (istio-operator.tmpl.yaml yaml /apiVersion/ /monitoring: true/)
    ```yaml
    apiVersion: install.istio.io/v1alpha1
    kind: IstioOperator
    spec:
      profile: empty
      tag: $ISTIO_VERSION-distroless
      components:
        base:
          enabled: true
        pilot:
          enabled: true
          k8s:
            overlays:
            - apiVersion: v1
              kind: ServiceAccount
              name: istio-pilot-service-account
              patches:
              - path: metadata.annotations
                value:
                  iam.gke.io/gcp-service-account: istio-proxy-telemetry-system@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
        ingressGateways:
        - enabled: true
          k8s:
            overlays:
            - apiVersion: v1
              kind: ServiceAccount
              name: istio-ingressgateway-service-account
              patches:
              - path: metadata.annotations
                value:
                  iam.gke.io/gcp-service-account: istio-proxy-telemetry-system@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
      values:
        global:
          enableTracing: true
          proxy:
            excludeIPRanges: 169.254.169.254/32 # metadata server
            tracer: stackdriver
        pilot:
          traceSampling: 100.0 # sample 100%, do not use this value for production
        telemetry:
          enabled: true
          v2:
            enabled: true
            prometheus:
              enabled: false
            stackdriver:
              enabled: true
              logging: true
              monitoring: true
    ```

    </walkthrough-alt>

    The `overlays` sections add the Workload Identity annotations to the
    Kubernetes service accounts for Istio's Pilot and Ingress Gateway
    components. These annotations bind the Kubernetes service accounts to the
    Cloud IAM service account you created for Istio system components.

    **Note:** In this tutorial you bind the Kubernetes service accounts for
    the Pilot and Ingress Gateway components to the same Cloud IAM service
    account. In your own environment you can bind them to separate Cloud IAM
    service accounts if you like.

    The `excludeIPRanges` parameter ensures that Istio sidecar proxies don't
    intercept requests to the
    [GKE metadata server](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#using_from_your_code)
    running on each node.

    See the Istio documentation for a
    [full reference of Istio operator configuration options](https://istio.io/docs/reference/config/istio.operator.v1alpha1/).

    **Note:** This manifest sets the `traceSampling` value to `100.0`. This
    value is a percentage, and it means that all incoming requests are
    selected for trace sampling. This is useful in tutorials and for
    demonstration purposes, but it will result in excessive trace data capture
    in high-traffic environments. For a production environment, you should use
    a smaller value for `traceSampling`, such as `1` or `0.1`.

4.  Install Istio using the `istioctl` tool and the Istio operator manifest:

    ```bash
    ./istioctl manifest apply \
            --filename <(envsubst < istio-operator.tmpl.yaml) \
            --skip-confirmation \
            --wait
    ```

    **Note:** If you would like to inspect the manifest before applying it,
    you can use the
    [`istioctl manifest generate` command](https://istio.io/docs/reference/commands/istioctl/#istioctl-manifest-generate).

## Deploying the sample app

1.  In Cloud Shell, apply the sample app manifest:

    ```bash
    envsubst < app.tmpl.yaml | kubectl apply -f -
    ```

2.  Inspect the Kubernetes manifest you used to deploy the sample app. The
    manifest contains multiple resources:

    -   a namespace called `demo`, with the `istio-injection` label to
        automatically inject the Istio sidecar proxy to all pods in the
        namespace;
    -   a Kubernetes service account called `app` with the Workload Identity
        annotation `iam.gke.io/gcp-service-account` to bind it to a Cloud IAM
        service account;
    -   a deployment with a pod spec (`template`) that specifies a container
        called `echo` and the `app` Kubernetes service account;
    -   a Service resource of type `ClusterIP`; and
    -   an Istio VirtualService resource that routes all requests arriving at
        the Istio Ingress Gateway to the sample app.

    <walkthrough-editor-select-line
        filePath="cloudshell_open/community/tutorials/istio-proxy-telemetry-operations-suite-workload-identity/app.tmpl.yaml"
        startLine="15" startCharacterOffset="0"
        endLine="15" endCharacterOffset="0"
        text="Open app.tmpl.yaml">
    </walkthrough-editor-select-line>

    <walkthrough-alt>

    `app.tmpl.yaml`:

    [embedmd]:# (app.tmpl.yaml yaml /apiVersion/ /host: app/)
    ```yaml
    apiVersion: v1
    kind: Namespace
    metadata:
      name: demo
      labels:
        istio-injection: enabled
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: app
      namespace: demo
      annotations:
        iam.gke.io/gcp-service-account: istio-proxy-telemetry-app@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: app
      namespace: demo
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: sampleapp
      template:
        metadata:
          labels:
            app: sampleapp
        spec:
          containers:
          - image: gcr.io/google-containers/echoserver:1.10@sha256:cb5c1bddd1b5665e1867a7fa1b5fa843a47ee433bbb75d4293888b71def53229
            name: echo
            ports:
            - containerPort: 8080
          serviceAccountName: app
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: app
      namespace: demo
    spec:
      type: ClusterIP
      selector:
        app: sampleapp
      ports:
      - name: http-app
        port: 80
        protocol: TCP
        targetPort: 8080
    ---
    apiVersion: networking.istio.io/v1beta1
    kind: VirtualService
    metadata:
      name: app
      namespace: demo
    spec:
      hosts:
      - '*'
      gateways:
      - istio-system/ingressgateway
      http:
      - name: route-app
        route:
        - destination:
            host: app
    ```

    </walkthrough-alt>

3.  Get the external IP address of the Istio Ingress Gateway service and store
    it in the `EXTERNAL_IP` environment variable:

    ```bash
    EXTERNAL_IP=$(kubectl get service istio-ingressgateway -n istio-system \
        --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
    ```

4.  Send a HTTP GET request to the sample app and inspect the status code:

    ```bash
    curl -si $EXTERNAL_IP | head -n1
    ```

    The output looks like this:

    ```
    HTTP/1.1 200 OK
    ```

    The first request can take some time while waiting for all the resources to
    become ready.

## Viewing logs in Cloud Logging

You can see logs from both Istio components and the sample app in Cloud
Logging.

1.  In the Cloud Console, go to **Logging** and open the **Logs Viewer**
    page:

    [Go to the Logs Viewer page](https://console.cloud.google.com/logs/query)

2.  In the **Query builder** pane, paste the following query and click
    **Run Query**:

    ```
    resource.labels.cluster_name="istio-proxy-telemetry"
    resource.labels.namespace_name="demo"
    resource.labels.container_name="echo"
    resource.type="k8s_container"
    ```

    The **Query results** pane shows logs from the sample app `echo` containers
    in the `demo` namespace.

    **Note:** If you don't see log messages, wait a minute and try again.

3.  In the **Query builder** pane, replace the existing query with the
    following query and click **Run Query**:

    ```
    resource.labels.cluster_name="istio-proxy-telemetry"
    resource.labels.namespace_name="istio-system"
    resource.labels.container_name="discovery"
    resource.type="k8s_container"
    ```

    The **Query results** pane shows logs from containers called `discovery` in
    the `istio-system` namespace. These are the containers from the
    [`istiod` component](https://istio.io/blog/2020/istiod/).

## Viewing metrics in Cloud Monitoring

You can see
[Istio metrics](https://cloud.google.com/monitoring/api/metrics_istio)
for the sample app in Cloud Monitoring.

**Note:** If this is the first time you access Cloud Monitoring functionality
for your Google Cloud project, your project is associated with a
[Workspace](https://cloud.google.com/monitoring/workspaces). If you've never
used Cloud Monitoring, a Workspace is automatically created.

1.  In the Cloud Console, go to **Monitoring** and open the
    **Metrics explorer** page:

    [Go to the Metrics explorer page](https://console.cloud.google.com/monitoring/metrics-explorer)

2.  In the **Metric** pane, define the following metric:

    -   **Resource type:** Kubernetes Container (`k8s_container`)
    -   **Metric:** Server Response Latencies
        (`istio.io/service/server/response_latencies`)
    -   **Group By:** `destination_workload_name`
    -   **Aggregator:** 99th percentile

3.  Select **Stacked Bar** from the chart type drop-down list in the chart
    pane.

    The chart shows 99th percentile response latencies for the sample app.

    If you like, you can add other Istio metrics by searching for metrics with
    the `istio.io/` prefix.

## Viewing traces in Cloud Trace

You can see traces from the sample app in Cloud Trace. The Istio sidecar
proxies reports these traces to Cloud Trace.

1.  In the Cloud Console, go to **Trace** and open the
    **Trace list** page:

    [Go to the Trace list page](https://console.cloud.google.com/traces/list)

2.  In the **Add trace filter** field (or the **Request filter** field if you
    use the classic Trace List view), enter this filter and press Enter:

    ```
    user_agent:curl
    ```

    You can see the trace for the request you made to the sample app
    using `curl`.

    **Note:** You won't see end-to-end traces for the sample app. To see
    end-to-end traces, your app must implement
    [trace context propagation](https://istio.io/docs/tasks/observability/distributed-tracing/overview/).

## Troubleshooting

If you run into problems with this tutorial, please review these documents:

-   [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
-   [GKE troubleshooting](https://cloud.google.com/kubernetes-engine/docs/troubleshooting)
-   [Cloud IAM troubleshooting access](https://cloud.google.com/iam/docs/troubleshooting-access)
-   [Cloud Logging troubleshooting](https://cloud.google.com/logging/docs/logs-based-metrics/troubleshooting)
-   [Cloud Monitoring API troubleshooting](https://cloud.google.com/monitoring/api/troubleshooting)
-   [Cloud Trace troubleshooting](https://cloud.google.com/trace/docs/troubleshooting)

## Cleaning up

To avoid incurring continuing charges to your Google Cloud Platform account for
the resources used in this tutorial you can either delete the project or delete
the individual resources.

### Deleting the project

**Caution:**  Deleting a project has the following effects:

-   **Everything in the project is deleted.** If you used an existing project
    for this tutorial, when you delete it, you also delete any other work
    you've done in the project.

-   **Custom project IDs are lost.** When you created this project, you might
    have created a custom project ID that you want to use in the future. To
    preserve the URLs that use the project ID, such as an `appspot.com` URL,
    delete selected resources inside the project instead of deleting the whole
    project.

In Cloud Shell, run this command to delete the project:

```bash
echo $GOOGLE_CLOUD_PROJECT ; gcloud projects delete $GOOGLE_CLOUD_PROJECT
```

### Deleting the resources

If you want to keep the Google Cloud project you used in this tutorial, delete
the individual resources.

1.  In Cloud Shell, delete the GKE cluster:

    ```bash
    gcloud container clusters delete istio-proxy-telemetry --async --quiet
    ```

2.  Delete the Cloud IAM role bindings:

    ```bash
    for ROLE in logging.logWriter monitoring.metricWriter cloudtrace.agent ; do
        for SA in istio-proxy-telemetry-system istio-proxy-telemetry-app ; do
            gcloud projects remove-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
                --member serviceAccount:$SA@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
                --role roles/$ROLE > /dev/null
        done
    done
    ```

3.  Delete the Cloud IAM service accounts:

    ```bash
    for SA in istio-proxy-telemetry-system istio-proxy-telemetry-app ; do
        gcloud iam service-accounts delete --quiet \
            $SA@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
    done
    ```

## What's next

-   Discover
    [Anthos Service Mesh](https://cloud.google.com/anthos/service-mesh),
    a fully managed service mesh based on Istio.
=   Learn more about
    [Google Cloud's operations suite for GKE](https://cloud.google.com/monitoring/kubernetes-engine).
-   Try out other Google Cloud features for yourself. Have a look at our
    [tutorials](https://cloud.google.com/docs/tutorials).

