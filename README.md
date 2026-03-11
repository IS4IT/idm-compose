# IDM Development environment composed with Docker

Build and manage disposable NetIQ Identity Manager environments for development, testing and learning about IDM containers on Docker.

![Alt text](idm-compose.gif?raw=true "idm-compose init")

## Requirements

- `docker` and `docker compose` (also works with Docker Desktop)
- `bash`, `envsubst`, `find`, `grep`, `keytool`, `openssl`, `sed`, `tr`, `zip`
- docker images specified in `compose.yaml_template` locally available or pullable
- `ca.crt` imported as a trusted root CA certificate into your browser
- the following entries added to `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts`) on your docker host:

```txt
 127.0.0.1 apps.idm.local
 127.0.0.1 db.idm.local
 127.0.0.1 forms.idm.local
 127.0.0.1 idcon.idm.local
 127.0.0.1 idv.idm.local
 127.0.0.1 iman.idm.local
 127.0.0.1 mq.idm.local
 127.0.0.1 osp.idm.local
 127.0.0.1 sspr.idm.local
 ```

- If you run Docker inside a virtual machine (rather than Docker Desktop or Colima) and want to access IDM from the VM host machine, also add the above hostnames to `/etc/hosts` on the VM host, replacing `127.0.0.1` with the VM's IP address.

## Tested on

- macOS (Intel and Apple Silicon) with
  - [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  - [Colima](https://github.com/abiosoft/colima)
  - [Rancher Desktop](https://rancherdesktop.io/)
- Ubuntu 24.04
  - must be able to run x86_64 container (natively or through multi-arch support + Rosetta, UTM, QEMU...)
  - distribution-provided docker packages:
    - docker-ce
    - docker-ce-cli
    - docker-buildx-plugin
    - docker-compose-plugin
    - java-common
- SLES 15.7

## Quickstart

### Create a new IDM stack

- Clone or copy this folder
- Run:

```sh
./idm-compose init <1..63>
```

### List all IDM stacks

```sh
./idm-compose ls
```

### Switch to an IDM stack

```sh
./idm-compose stack <1..63>
```

### Print current IDM stack

```sh
./idm-compose stack
```

### Start an IDM stack

```sh
./idm-compose start
```

### Stop an IDM stack

```sh
./idm-compose stop
```

### Delete an IDM stack

```sh
./idm-compose wipe
```

## Key concepts

Running NetIQ Identity Manager as a containerized service is described briefly in the [product documentation](https://www.netiq.com/documentation/identity-manager-49/setup_linux/data/t44hxf3fe2mn.html) and is targeted towards production environments.

This tool, on the other hand, is primarily for easily creating IDM environments for development, testing, and learning. `idm-compose` uses `docker build` and `docker compose` to work around quirks and issues in the original Docker images, enabling quick environment initialization with minimal manual configuration.

### Stacks

`idm-compose` allows you to create up to 63 IDM stacks in parallel, numbered 1–63. Each stack has a name, subnet, and published port range derived from its ID. For example, run `idm-compose init 27` to create stack 27, which will be named `idm-compose27`, use subnet `x.y.27.0/24`, and publish applications on ports `27xxx`. The compose file and selected profiles for each stack are stored in the `stacks` subfolder.

Switch between stacks with `idm-compose stack <stack id>`. Running `idm-compose stack` without a stack ID prints the currently selected stack details. Instead of switching between stacks, you can specify the stack to work on by setting the `STACK` environment variable, for example: `STACK=3 idm-compose stop`

To remove all containers, volumes, and images for a given stack, run `idm-compose wipe <stack id>` and confirm deletion.

If you want to run just a single stack, no stack id needs to be provided and stack 1 is being used.

### Profiles

All IDM services are part of one or more profiles. The default profiles to be installed are set in `idm-compose.conf` and can be overridden by setting the `COMPOSE_PROFILES` environment variable, for example:

```sh
COMPOSE_PROFILES="idv,rl,iman" idm-compose init
```

Individual profiles are predefined for each container. The following combined container profiles are also available:

- `dirxml`: ID Vault, Remote Loader, ID Console
- `apps`: ID Vault, Remote Loader, ID Console, OSP, ID Apps, Forms, SSPR, Database
- `all`: All services

### Networking

Unlike the single-server setup described in the documentation, which uses `host` networking, `idm-compose` sets up `bridge` networking and maps only selected ports to the `localhost` interface. This allows multiple isolated environments to coexist and keeps them unexposed to the outside world.

Networking can be configured in `compose.yaml_template` to bind to `0.0.0.0` instead of just `localhost`. This is required if Docker runs inside a virtual machine and IDM must be accessible from the host machine. In that case, the `*.idm.local` entries in `/etc/hosts` must point to the VM's IP address instead of `127.0.0.1`.

Instead of using networking parameters derived from the stack ID, you can override them by setting the `SUBNET`, `PORT_BASE`, and `TREENAME` environment variables before calling `idm-compose` to avoid conflicts with other software.

### PKI & Certificates

The Identity Applications rely heavily on verified and trusted TLS connections, which can be a significant challenge when quickly setting up isolated, disposable dev/test environments. `idm-compose` works around this by creating its own local CA and wildcard server certificate for all exposed web services. The same CA is used for all stacks, so its public key needs to be imported into your browser only once.

Instead of using a local CA, you can provide your own `ca.key` and `ca.crt` files (PEM format), which will be used to sign the server certificate.

You can also provide an already-signed wildcard server certificate and private key (`server.key`, `server.crt`, and `ca.crt`), eliminating the need for a local CA. Ensure that `ca.crt` is also provided in this case.

### Customized Images

The official IDM docker images provided by OpenText are used as base images to build enhanced and/or bug fixed images on top of them. A Dockerfile for each image can be found under the `images` subfolder.

### Command pass-through

`idm-compose` handles only the `init`, `wipe`, and `stack` commands itself; all other commands are passed through to `docker compose`.

See `idm-compose --help` for more details.

## Configuration

- Defaults can be set in [`idm-compose.conf`](idm-compose.conf) and apply to all created stacks unless individually overridden.
- Add files and folders to the `config` subfolder for further customization, such as:
  - Add `.jar` and `.so` files to `config/idm/mountfiles` and `config/rdxml/mountfiles` to install or update shims or libraries
  - Add `.ldif` and `.sch` files to `config/idm/mountfiles` to extend schema or prepopulate eDirectory

## Troubleshooting

Some containers support debugging. Set the `debug` environment variable in `stacks/<1..63>/compose.yaml` and restart the container.

While `idm-compose` is working, you may want to follow its progress in more detail by running the following commands in separate terminals once the `idv` container is running:

```sh
./idm-compose logs -f
```

```sh
./idm-compose exec idv tail -qFn0 /config/userapp/tomcat/logs/catalina.out /config/osp/tomcat/logs/catalina.out
```

## Known issues

### idv

- Occasionally, the schema does not get extended properly, which causes the apps container to fail installing the UserApp and RRSD drivers.
- Sometimes IDM cannot be configured and fails with "Could not find prompt ID" even though the listed prompt is set in `/config/silent.properties`.

### apps

- `IDMProv.war` cannot be deployed completely; `catalina.out` shows:

  ```log
  org.apache.catalina.startup.HostConfig.deployWAR Error deploying web application archive [/opt/netiq/idm/apps/tomcat/webapps/IDMProv.war]
  ```

  - **Workaround**: Delete the `/opt/netiq/idm/apps/tomcat/webapps/IDMProv` folder and restart the container.

### sspr

- Server certificate is not imported automatically.
  - **Workaround**: Unlock the configuration by editing `/config/SSPRConfiguration.xml` or running `/app/command.sh ConfigUnlock` inside the container.
  - Open <https://sspr.idm.local:2445/sspr/private/config/editor> and import `keys.pfx` (PKCS12, Alias: `tomcat`).
  - Lock the configuration.
  - Restart the container.
- SSPR shows a blank page after login due to OAuth/PKI error:

  ```log
  5057 ERROR_SERVICE_UNREACHABLE (error while making http request: no root CA certificates in configuration trust store)
  ```

## To Do

- Polish stack support
- Fix SSPR container certificates
- Add reporting and fanout containers

## Performance

It takes approximately 20 minutes to initialize a complete environment on an M3 MacBook Pro with Docker Desktop (using Virtualization Framework + Rosetta). A minimal IDM engine environment (`idv`, `rl`, `idcon`, `iman`) without Identity Apps is ready in about 5 minutes.
