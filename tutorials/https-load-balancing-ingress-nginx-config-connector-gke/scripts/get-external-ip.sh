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

# [START gclb_ingress_nginx_cc_scripts_get_external_ip]
get_reserved_ip () {
    reserved_ip=$(kubectl get computeaddress \
        gclb-ingress-nginx-cc-tutorial-address \
        -o jsonpath='{.spec.address}')
}
get_reserved_ip
while [ -z "$reserved_ip" ]; do
    sleep 2
    get_reserved_ip
done
echo "$reserved_ip"
# [END gclb_ingress_nginx_cc_scripts_get_external_ip]
