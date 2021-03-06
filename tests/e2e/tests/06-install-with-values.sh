#!/bin/bash

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/../../..)

# shellcheck source=../common.sh
source "$this_dir/../common.sh"

########################################################################################################################
# local variables
########################################################################################################################

# the versions of Ambassador to install
AMB_VERSION="1.6.0"

# `image.tag` that will be forced in a helmvalue
AMB_IMAGE_TAG="1.5.5"

########################################################################################################################

[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

########################################################################################################################

pushd "$TOP_DIR" >/dev/null || exit 1

info "Installing the Operator..."
oper_install "yaml" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Installing Ambassador with some values..."
# see https://github.com/datawire/ambassador-chart#configuration for values
cat <<EOF | kubectl apply -n "$TEST_NAMESPACE" -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_NAME}
spec:
  version: "*"
  logLevel: info
  helmValues:
    deploymentTool: amb-oper-kind
    replicaCount: 1
    namespace:
      name: ${TEST_NAMESPACE}
    image:
      pullPolicy: Always
    image.tag: ${AMB_IMAGE_TAG}
    service:
      ports:
      - name: "http"
        port: 80
        targetPort: 8080
EOF

# TODO: for some unknown reason, we cannot mix packed-form with free-form
#    service.ports[1].name: https
#    service.ports[1].port: 443
#    service.ports[1].targetPort: 8443

oper_wait_install_amb -n "$TEST_NAMESPACE" || abort "the Operator did not install Ambassador"

info "Checking Ambassador values:"
values="$(helm get values -n "$TEST_NAMESPACE" ${AMB_INSTALLATION_NAME})"
echo "$values"

echo "$values" | grep -q -E "name: $TEST_NAMESPACE" || abort "no namespace found in values"
echo "$values" | grep -q -E "name: http" || abort "no http port found in values"
echo "$values" | grep "targetPort" | grep -q "8080" || abort "no targetPort: 8080 found in values"

info "Checking the version of Ambassador that has been deployed is $AMB_IMAGE_TAG..."
if ! amb_check_image_tag "$AMB_IMAGE_TAG" -n "$TEST_NAMESPACE"; then
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi
passed "... good! The version is $AMB_VERSION_FIRST"

exit 0
