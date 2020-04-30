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

# [START gclb_ingress_nginx_cc_scripts_wait_certificate]
get_cert_status () {
    echo "Checking SSL certificate status..."
    status=$(gcloud compute ssl-certificates describe \
        gclb-ingress-nginx-cc-tutorial-ssl-certificate \
        --format 'value(managed.status)')
}
get_cert_status
while [ "$status" != "ACTIVE" ]; do
    sleep 15
    get_cert_status
done
echo "Certificate is active"
# [END gclb_ingress_nginx_cc_scripts_wait_certificate]
