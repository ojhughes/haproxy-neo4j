VERSION = 0.2.1
TLS_CN != if [ X"$(TLS_CN)" = X"" ]; then \
		echo "localhost"; \
	else \
		echo "${TLS_CN}"; \
	fi

KEYGEN = openssl req -x509 -newkey rsa:2048 -sha256 -keyout cert.pem.key \
		-out cert.pem -days 30 -nodes -config ssl.conf


.PHONY: docker k8s-deploy clean
.NOTPARALLEL: certs

docker:
	docker build -t eu.gcr.io/launcher-development-191917/haproxy-neo4j:$(VERSION) .
	docker push eu.gcr.io/launcher-development-191917/haproxy-neo4j:$(VERSION)

ssl.conf:
	printf \
"[ req ] \n\
	prompt = no \n\
	distinguished_name = req_distinguished_name \n\
	x509_extensions = san_self_signed \n\
[ req_distinguished_name ] \n\
	CN=$(TLS_CN) \n\
[ san_self_signed ] \n\
	subjectAltName = DNS:$(TLS_CN) \n\
	subjectKeyIdentifier = hash \n\
	authorityKeyIdentifier = keyid:always,issuer \n\
	basicConstraints = CA:false \n\
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment, keyCertSign, cRLSign \n\
	extendedKeyUsage = serverAuth, clientAuth, timeStamping\n" > ssl.conf

certs: ssl.conf cert.pem cert.pem.key
cert.pem:
	$(KEYGEN)
cert.pem.key:
	$(KEYGEN)

k8s-tls-secret: certs
	kubectl create secret tls haproxy-neo4j-tls-secret \
		--cert=cert.pem \
		--key=cert.pem.key \
		--dry-run=client -o yaml | kubectl apply -f -

k8s-deploy: k8s-tls-secret

clean:
	@echo make clean
	rm -f ssl.conf cert.pem cert.pem.key
