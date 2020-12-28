# HAProxy for Neo4j

> “Let us therefore trust the eternal Spirit which destroys and
> annihilates only because it is the unfathomable and eternally
> creative source of all life. The passion for destruction is also a
> creative passion.”
>   - Mikhail Bakunin, "The Reaction in Germany", 1842

This is fun little project that experiments with using the powers of
[haproxy](https://haproxy.org) to solve a few fun networking things
with Enterprise Neo4j deployments:

1. Corporate firewalls HATE ports != 80 or 443
2. Neo4j typically requires both HTTP(s) and Bolt ports exposed
3. The default port for Bolt is 7687, which is not 80 nor is it 443
4. I love networking nonsense

## So What Nonsense am I up to Now?
Diagram to be inserted, but as part of some experimentation with Neo4j
clusters using Server-Side Routing, I wanted to try combining some
[previous work](https://github.com/voutilad/haproxy-and-neo4j) tuning
HAProxy to handle some intelligent Layer 7 routing of all requests
needed for apps like Neo4j Browser.

### In English?
SO! Neo4j Browser is typically hosted by Neo4j's built-in web
app. This is exposed either via http or https typically on ports 7474
or 7473 respectively. All fine and dandy, but those ports are unknowns
to corporate firewalls so usually my customers can't access systems I
build if I expose those ports publicly.

So the easy solution is to have an HTTP reverse proxy from 80/443 to
7474/7473 (respectively), right?

Yeah. But that only gets you Neo4j Browser...you still need a Bolt
connection.

Bolt servers typically run on TCP port 7687, another port poo-poo'd by
corporate firewalls.

> Q: But wait, can't Bolt work over WebSockets?
> A: Yes, BUT...the hardcoded HTTP path we expect is still `/`, so
> it's not possible at the moment to get Neo4j to host Browser AND a
> Bolt WebSocket listener on the same TCP port. *le sigh*

I've shown [before](https://github.com/voutilad/haproxy-and-neo4j) how
to use some features of HAProxy to sniff the initial opening request
to intelligently reverse proxy HTTP requests and Bolt requests to
differing Neo4j ports, including handling Bolt-atop-WebSockets.

This project extends this into the realm of Kubernetes.

*But, why?* I wanted to see if I could recreate the same simplicity as
I did before: expose a single hostname via publicly accessible DNS
that lets a corporate citizen access Browser and Bolt running from a
Neo4j Causal Cluster in my Kubernetes environment.

### Explaining the Magic
There's one particular piece of Magic that's required: /hacking the
Discovery json response from Neo4j's http interface/api/.

Browser, at first launch, sends a `GET /` to the root of the server
that's hosting it, and sets an HTTP header of `Accept:
application/json` causing the web app in Neo4j to respond with a JSON
blob looking like:

```json
{
  "bolt_routing": "neo4j://some-host:7687",
  "dbms/cluster": "http://some-host/dbms/cluster",
  "db/cluster": "http://some-host/db/{databaseName}/cluster",
  "transaction": "http://some-host/db/{databaseName}/tx",
  "bolt_direct": "bolt://some-host:7687",
  "neo4j_version" : "4.2.1",
  "neo4j_edition" : "enterprise"
}
```

This blob is populated based on the *advertised addresses* set for
things like the HTTP and Bolt connectors.

We need this to point Browser to our externally facing host.

> Q: Ok, why don't you just set an advertised address and be done with
> it?
> A: That's not magic. And that's a pain in the butt. And that is
> intrusive configuration that's a source of numerous headaches as
> I've [talked about before](https://github.com/voutilad/bolt-proxy)

Using the power of Lua scripting, [discovery.lua](./discovery.lua) is
used to process any HTTP GET requests that look like they're asking
for this discovery json. Instead of reverse proxying them to Neo4j, we
run the custom Lua code that does it's own request to the backend and
mutates the response to look like WE WANT IT TO based on the HAProxy
config file (bake into the Docker image).

> The one caveat: we have to assume TLS and tack on :443 to the
> hostname because the neo4j-javascript-driver will take any Bolt url
> that doesn't explicitly mention a port number and use :7687. Ugh.

## Building
Simple! Just decide on what your hostname of choice will be for the
certificate (or not if you want to use "localhost" and have things
complain):

```
$ TLS_CN=myhostname.domain.something make
```

You'll end up with a new Docker image `haproxy-neo4j` tagged with a
version, an x509 cert in pem format (`cert.pem`), signed with a
private key in PEM format (`cert.pem.key`).

## Using
The HAProxy image is based off the publicly available image in
DockerHub and provides:

1. A preconfigured

## Example Deployment for GKE
So you want to try this out? Deploy the following things to GKE or
your k8s of choice. Replace anything in braces like `<<>>` with your
own details.

### TLS Secret
We need to first install the x509 cert and key as a kubernetes TLS
secret. If you have a cert and key you'd like to use instead, change
this as you see fit. You'll reference it in the next section for the
Deployment config, btw.

Easiest way is from the command line after having run `make` or `make
certs` (setting `TLS_CN` appropriately)
```
$ kubectl create secret tls haproxy-neo4j-tls-secret \
    --cert=cert.pem \
    --key=cert.pem.key
```

> You might notice my funny naming convention. It's from HAProxy's
> requirement of either having the key and cert appended together into
> 1 PEM file OR having the key use the same name as the cert, just
> with `.key` as a suffix. Here k8s is going to muck with it, but for
> local testing, I keep the files like that. We'll revisit this point
> next section.

### Deployment
The following Deployment defines the HAProxy deployment as a stateless
set of pods. Feel free to change the number of replicas, etc. as you
see fit.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: haproxy-neo4j-deployment
  labels:
    app: haproxy-neo4j
spec:
  replicas: 2
  selector:
    matchLabels:
      app: haproxy-neo4j
  template:
    metadata:
      labels:
        app: haproxy-neo4j
    spec:
      containers:
      - name: haproxy-neo4j
        image: us.gcr.io/<<YOUR-GCP-PROJECT>>/haproxy-neo4j:0.1.2
        env:
        - name: NEO4J_HTTP
          value: "<<YOUR-K8S-NEO4J-SERVICE>>:7474"
        - name: NEO4J_BOLT
          value: "<<YOUR-K8S-NEO4J-SERVICE>>:7687"
        volumeMounts:
          - name: haproxy-neo4j-tls-secret-volume
            mountPath: "/etc/ssl/haproxy"
            readOnly: true
        ports:
          - containerPort: 8080
          - containerPort: 8443
      volumes:
        - name: haproxy-neo4j-tls-secret-volume
          secret:
            secretName: haproxy-neo4j-tls-secret
            items:
            - key: tls.crt
              path: cert.pem
            - key: tls.key
              path: cert.pem.key
```

> Above, you should notice the mapping of the TLS secret as a
> volume. Note the renaming of the keys `tls.crt` nad `tls.key` to
> `cert.pem` and `cert.pem.key` respectively. This does what I was
> talking about before...it makes the secret available in an
> HAProxy-friendly format.

### A Load Balancer
This only works with GKE. If using something else, or substituting a
NodePort, you're on your own for now.

Since I'm assuming GKE, just go get a static External IP in your GKE
node pools region and substitute in here:

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/name: haproxy-neo4j-lb
    app.kubernetes.io/instance: haproxy-neo4j-lb
  name: haproxy-neo4j-lb
spec:
  loadBalancerIP: <<YOUR-EXTERNAL-IP>>
  externalTrafficPolicy: Local
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: 8080
    - name: https
      port: 443
      protocol: TCP
      targetPort: 8443
  selector:
    app: haproxy-neo4j
  sessionAffinity: None
  type: LoadBalancer

```

## See Also
- My Layer-7 bolt proxy: https://github.com/voutilad/bolt-proxy
