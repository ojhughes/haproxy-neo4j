VERSION = 0.1.2
TLS_CN != if [ X"$(TLS_CN)" = X"" ]; then \
		echo "localhost"; \
	else \
		echo "${TLS_CN}"; \
	fi

KEYGEN = openssl req -x509 -newkey rsa:4096 -keyout cert.pem.key \
		-out cert.pem -days 30 -nodes -subj "/CN=${TLS_CN}"


.PHONY: docker k8s-deploy clean
.NOTPARALLEL: certs

docker: certs
	docker build -t haproxy-neo4j:$(VERSION) .

certs: cert.pem cert.pem.key
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
	rm -f cert.pem cert.pem.key
