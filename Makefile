TLS_CN != if [ X"$(TLS_CN)" = X"" ]; then \
		echo "localhost"; \
	else \
		echo "${TLS_CN}"; \
	fi

KEYGEN = openssl req -x509 -newkey rsa:4096 -keyout key.pem \
		-out cert.pem -days 30 -nodes -subj "/CN=${TLS_CN}"


.PHONY: docker clean
.NOTPARALLEL: certs

docker: certs
	docker build -t neo4j-haproxy:latest .

certs: cert.pem key.pem
cert.pem:
	$(KEYGEN)
key.pem:
	$(KEYGEN)

clean:
	@echo make clean
	rm -f cert.pem key.pem
