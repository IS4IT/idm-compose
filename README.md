# IDM Development environment composed with Docker

Build and manage disposable NetIQ Identity Manager environments for development, testing and learning about IDM containers on Docker.

![Alt text](idm-compose.gif?raw=true "idm-compose init")

## Requirements

- `docker` and `docker compose` (also works with Docker Desktop)
- `bash`, `openssl`, `sed`, `find`, `grep`, `envsubst`, `tr`, `keytool`
- docker images specified in `compose.yaml_template` locally available or pullable
- `ca.crt` imported as a trusted root CA certificate into your browser
- the follwing entries added to `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts`) on your docker host:
```
 127.0.0.1	apps.idm.local
 127.0.0.1	db.idm.local
 127.0.0.1	forms.idm.local
 127.0.0.1	idcon.idm.local
 127.0.0.1	idv.idm.local
 127.0.0.1	iman.idm.local
 127.0.0.1	mq.idm.local
 127.0.0.1	osp.idm.local
 127.0.0.1	sspr.idm.local
 ```
- If you run docker inside a virtual machine (rather than in Docker Desktop or Colima) and want to access IDM from the VM host machine, also add the above hostnames to `/etc/hosts` on the VM host, replacing "127.0.0.1" with the VM's IP address.

Tested on 
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

## Quickstart

#### Create a new IDM stack

- clone or copy this folder
- run `./idm-compose init (<1..63>)`

#### List all IDM stacks (along with all non-IDM stacks)

- run `./idm-compose ls`

#### Switch to an IDM stack

- run `./idm-compose stack <1..63>`

#### Print current IDM stack

- run `./idm-compose stack`

#### Start an IDM stack

- run `./idm-compose start`

#### Stop an IDM stack

- run `./idm-compose stop`

#### Delete an IDM stack

- run `./idm-compose wipe`

#### Optional:
- change defaults in idm.compose.conf
- add files/folders to `config` subfolder for further customization, e.g.
  - add .jar/.so files to the `config/idm/mountfiles` and `config/rdxml/mountfiles` subfolders to install or updated shims or libraries
  - add .ldif/.sch files to `config/idm/mountfiles` to extend schema and/or prepopulate Edirectory

## Key concepts

Running NetIQ Identity Manager as a containerized service is described briefly in the [product documentation](https://www.netiq.com/documentation/identity-manager-49/setup_linux/data/t44hxf3fe2mn.html) and is targeted towards production environments. 

This tool on the other hands is primarily about easily creating IDM environments for development, testing and learning. `idm-compose` utilizes `docker build` and `docker compose` to work around the quirks and issues that come with the original docker images and initialize new environments quickly and without much manual configuration

#### Stacks

`idm-compose` allows to create up to 63 IDM stacks in parallel, numbered 1..63. Each stack has its name, subnet and published port range derived from its id. For example run `idm-compose init 27` to create stack 27, which will be named "idm-compose27" live on subnet x.y.27.0/24 and publish applications on ports 0.0.0.0:27xxx The compose file and the selected profiles for each stack will be stored in the `stacks` subfolder.

Switch between stacks with `idm-compose stack <stack id>`. Running `idm-compose stack` without a stack id prints the currently selected stack details. Instead of switching between stacks you can provide the stack to work on by setting the STACK environment variable, e.g. `STACK=3 idm-compose stop`

To remove all containers, volumes and images for a given stack, run `idm-compose wipe <stack id>` and confirm deletion.

If you want to run just a single stack, no stack id needs to be provided and stack 1 is being used.

#### Configuration

Some default can be set in `idm-compose.conf` and apply to all created stacks unless individually overridden.

#### Profiles

All IDM services are part of one or more profiles. The default profiles to be installed are set in `idm-compose.conf` and can be overridden by setting the COMPOSE_PROFILES environment variable e.g. `COMPOSE_PROFILES="idv,rl,iman" idm-compose init`. 

Individual profiles are predefined for each container, plus the following combined container profiles:
- dirxml: ID Vault, Remote Loader, ID Console
- apps: ID Vault, Remote Loader, ID Console, OSP, ID Apps, Forms, SSPR, Database
- all: all services
 
#### Networking

Unlike the single server setup described in the documentation, which uses `host` networking, `idm-compose` sets up `bridge` networking and only selected ports are mapped to the `localhost` interface. This allows for multiple isolated environments to co-exist and does not expose them to the outside world.

Networking can be configured in `compose.yaml_template` to bind to the default `0.0.0.0` instead of just `localhost`, which is required if docker runs inside a virtual machine and IDM shall be accessible from the host machine. In that case the `*.idm.local` entries in `/etc/hosts` need to point to the VM's IP address instead of `127.0.0.1`

Instead of using networking parameters derived from the stack id you can override them by setting the `SUBNET`, `PORT_BASE` and `TREENAME` environment variables prior to calling `idm-compose`, to avoid conflicts with other software.

#### PKI & Certificates

The Identity Applications rely heavily on verified and trusted TLS connections, which can be a major hassle and hinder quickly setting up isolated, disposable dev/test environments. `idm-compose` works around this by creating it's own local CA and wildcard server certificate for all exposed web services. The same CA is used for all stacks so it's public key needs to be imported into your browser only once.

Instead of using a local CA you can provide your own `ca.key` and `ca.crt`files (PEM format) and those will be used to sign the server certificate.

You can also provide an already signed wildcard server certificate and private key (`server.key`, `server.crt` and `ca.crt`), eliminating the need for a local CA in the first place. Make sure to also provide `ca.crt` in that case.

#### Customized Images

The official IDM docker images provided by OpenText are used as base images to build enhanced and/or bug fixed images on top of them. A Dockerfile for each image can be found under the `images` subfolder.

#### Command pass-through

`idm-compose` handles only the `ìnit`, `wipe` and `stack` commands by itself, all other commands are passed through to `docker compose`. 

See `idm-compose --help` for more details.

## Troubleshooting

Some containers support debugging, set the appropriate env variable in compose.yaml and restart the container.

While `idm-compose` is working you may want to follow its progress in more detail by running the following commands in separate terminals once the idv container is running:

```
./idm-compose logs -f
```
```
./idm-compose exec idv tail -qFn0 /config/userapp/tomcat/logs/catalina.out /config/osp/tomcat/logs/catalina.out
```

## Known issues

#### idv:
- Occationally the schema does not get extended properly, which causes the apps container to fail installing the UserApp and RRSD drivers.
- Sometimes IDM cannot be configured and fails with "Could not find prompt ID" even though the listed prompt is set in /config/silent.properties

#### apps:
- IDMProv.war cannot be deployed completely, catalina.out shows: ```org.apache.catalina.startup.HostConfig.deployWAR Error deploying web application archive [/opt/netiq/idm/apps/tomcat/webapps/IDMProv.war]```
  - Workaround: delete the `/opt/netiq/idm/apps/tomcat/webapps/IDMProv` folder and restart the container

#### sspr:
- Server certificate is not imported automatically
  - Workaround: unlock the configuration by editing /config/SSPRConfiguration.xml or running `/app/command.sh ConfigUnlock` inside the container
  - Open https://sspr.idm.local:2445/sspr/private/config/editor and import keys.pfx (PKCS12, Alias "tomcat")
  - Lock configuration
  - restart container
- SPPR shown blank page after login attempt due to OAuth/PKI error: `5057 ERROR_SERVICE_UNREACHABLE (error while making http request: no root CA certificates in configuration trust store`

## To Do

- polish STACK support
- fix SSPR container certificates
- add reporting and fanout containers

## Performance

It takes about 20 minutes to complete initializing a complete environment on an M3 MacBook Pro with Docker Desktop (using Virtualization Framework + Rosetta). A pure IDM engine environment (idv, rl, idcon, iman) without Identity Apps is ready in about 5 minutes.
