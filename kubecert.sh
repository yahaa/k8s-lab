#!/bin/bash
svcName=""
namespace="default"

usage() {
	cat <<EOF
Usage:
    kubecert.sh get cabundle
    kubecert.sh create secret
Examples:
    kubecert.sh get cabundle                               get cabundle from k8s cluster.
    kubecert.sh create secret svc-example                  create secret svc-example on default namespace,key.pem and cert.pem include in secret svc-example-secret.
    kubecert.sh create secret svc-example kube-system      create secret svc-example on kube-system namespace,key.pen and cert.pen.

EOF
}

initFlag() {
	if [ -n "$1" ]; then
		svcName=$1
	else
		usage
		exit 1
	fi

	if [ -n "$2" ]; then
		namespace=$2
	fi

}

getCaBundle() {
	CA_BUNDLE=$(kubectl get configmap -n kube-system extension-apiserver-authentication -o=jsonpath='{.data.client-ca-file}' | base64 | tr -d '\n')
	echo $CA_BUNDLE
}

createCert() {
	csrName=${svcName}.${namespace}
	tmpdir=$(mktemp -d)
	echo "creating certs in tmpdir ${tmpdir} "

	cat <<EOF >>${tmpdir}/csr.conf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${svcName}
DNS.2 = ${csrName}
DNS.3 = ${csrName}.svc
EOF

	openssl genrsa -out ${tmpdir}/server-key.pem 2048
	openssl req -new -key ${tmpdir}/server-key.pem -subj "/CN=${csrName}.svc" -out ${tmpdir}/server.csr -config ${tmpdir}/csr.conf

	# clean-up any previously created CSR for our service. Ignore errors if not present.
	kubectl delete csr ${csrName} 2>/dev/null || true

	# create  server cert/key CSR and  send to k8s API
	cat <<EOF | kubectl create -f -
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: ${csrName}
spec:
  groups:
  - system:authenticated
  request: $(cat ${tmpdir}/server.csr | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

	# verify CSR has been created
	while true; do
		kubectl get csr ${csrName}
		if [ "$?" -eq 0 ]; then
			break
		fi
	done

	# approve and fetch the signed certificate
	kubectl certificate approve ${csrName}
	# verify certificate has been signed
	for x in $(seq 10); do
		serverCert=$(kubectl get csr ${csrName} -o jsonpath='{.status.certificate}')
		if [[ ${serverCert} != '' ]]; then
			break
		fi
		sleep 1
	done
	if [[ ${serverCert} == '' ]]; then
		echo "ERROR: After approving csr ${csrName}, the signed certificate did not appear on the resource. Giving up after 10 attempts." >&2
		exit 1
	fi
	echo ${serverCert} | openssl base64 -d -A -out ${tmpdir}/server-cert.pem

	# create the secret with CA cert and server cert/key
	kubectl create secret generic ${svcName}-secret \
		--from-file=key.pem=${tmpdir}/server-key.pem \
		--from-file=cert.pem=${tmpdir}/server-cert.pem \
		--dry-run -o yaml |
		kubectl -n ${namespace} apply -f -
}

main() {
	case $1 in
	get)
		getCaBundle
		;;
	create)
		initFlag $2 $3
		createCert
		;;
	*)
		usage
		;;
	esac
}

main $1 $2 $3 $4
