#!/usr/bin/env bash
#
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euf -o pipefail

# [START gclb_ingress_nginx_cc_scripts_wait_backend]
get_backend_status () {
    echo "Checking backend service health..."
    status=$(gcloud compute backend-services get-health \
        gclb-ingress-nginx-cc-tutorial-backend-service \
        --global \
        --format 'value(status.healthStatus[0].healthState)')
}
get_backend_status
while [ "$status" != "HEALTHY" ]; do
    sleep 15
    get_backend_status
done
echo "Backend is healthy"
# [END gclb_ingress_nginx_cc_scripts_wait_backend]
