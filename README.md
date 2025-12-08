# IDM Development environment composed with Docker

Build and manage disposable NetIQ Identity Manager environments for development, testing and learning about IDM containers on Docker.

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

In order to pull images form hub.is4it.de, you may need to login first with `docker login hub.is4it.de`

Pulling images concurrently does not work well with hub.is4it.de, to prevent this configure your docker deamon with:
```
{
    "max-concurrent-uploads": 1,
    "max-concurrent-downloads": 1
}
```

## Known issues

#### idv:
- Occationally the schema does not get extended properly, which causes the apps container to fail installing the US and RRSD drivers.
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

## Example

```
$ COMPOSE_PROFILES=all ./idm-compose init
Executing docker compose with options: --project-directory .
Initializing stack idm-compose01 with profile(s): all
Using internal docker subnet 172.77.1.0/24  and ports mapped to  0.0.0.0:1389..1900
Creating compose.yaml from template...
Creating config/idm/mountfiles/import.sh from template...
envsubst: too many arguments
Creating config/mail/smtp.ldif from template...
Creating config/silent.properties from template...
Creating config/data/edirapi.conf from template...
Creating config/data/init.sql from template...
Creating images/identityconsole/Dockerfile from template...
Creating images/osp/Dockerfile from template...
Creating images/forms/Dockerfile from template...
Creating images/imanager/Dockerfile from template...
Creating images/userapp/Dockerfile from template...
Creating images/identityengine/Dockerfile from template...
Creating images/remoteloader/Dockerfile from template...
Creating images/sspr/sspr-webapp/Dockerfile from template...
compose.yaml -> stacks/01/compose.yaml
Installing services: apps db forms idcon idv iman mail osp rl sspr
Using existing keystore ./config/data/keys.pfx
Your keystore contains 2 entries
idm-local_ca, 30 Mar 2025, trustedCertEntry,
tomcat, 30 Mar 2025, PrivateKeyEntry,
 Not Before: Feb 25 17:41:22 2025 GMT
 Not After : Feb 23 17:41:22 2035 GMT
 Subject: CN=*.idm.local
 DNS:*.idm.local, IP Address:127.0.0.1
Importing keystore config/data/keys.pfx to images/iManager/.p12...
Entry for alias tomcat successfully imported.
Entry for alias idm-local_ca successfully imported.
Import command completed:  2 entries successfully imported, 0 entries failed or cancelled
updating: cert/nginx.crt (deflated 24%)
updating: cert/nginx.key (deflated 24%)
updating: cert/pass.txt (stored 0%)
server.crt -> config/mail/mail.crt
writing RSA key
config/mail/smtp.ldif -> config/idm/mountfiles/smtp.ldif
[+] Building 4.3s (117/117) FINISHED
 => [internal] load local bake definitions
 => => reading from stdin 2.99kB
 => [sspr internal] load build definition from Dockerfile
 => => transferring dockerfile: 560B
 => [iman internal] load build definition from Dockerfile
 => => transferring dockerfile: 1.47kB
 => [idcon internal] load build definition from Dockerfile
 => => transferring dockerfile: 921B
 => [idv internal] load build definition from Dockerfile
 => => transferring dockerfile: 561B
 => [osp internal] load build definition from Dockerfile
 => => transferring dockerfile: 549B
 => [apps internal] load build definition from Dockerfile
 => => transferring dockerfile: 569B
 => [forms internal] load build definition from Dockerfile
 => => transferring dockerfile: 288B
 => [rl internal] load build definition from Dockerfile
 => => transferring dockerfile: 408B
 => [sspr internal] load metadata for docker.io/sspr/sspr-webapp:4.8.0.1-533
 => [idv internal] load metadata for docker.io/library/identityengine:idm-4.10.0-533
 => [apps internal] load metadata for docker.io/library/identityapplication:idm-4.10.0-533
 => [osp internal] load metadata for docker.io/library/osp:idm-4.10.0-533
 => [rl internal] load metadata for docker.io/library/remoteloader:idm-4.10.0-533
 => [idcon internal] load metadata for docker.io/library/identityconsole:1.9.0.0000-533
 => [forms internal] load metadata for docker.io/library/formrenderer:idm-4.10.0-533
 => [iman internal] load metadata for hub.is4it.de/vendor/netiq/idm/imanager:3.2.6-p3
 ...
[+] Creating 22/22
 ✔ idv                              Built
 ✔ iman                             Built
 ✔ osp                              Built
 ✔ rl                               Built
 ✔ sspr                             Built
 ✔ apps                             Built
 ✔ forms                            Built
 ✔ idcon                            Built
 ✔ Network idm-compose01_default    Created
 ✔ Volume "idm-compose01_config"    Created
 ✔ Volume "idm-compose01_trace"     Created
 ✔ Volume "idm-compose01_cache"     Created
 ✔ Container idm-compose01-db-1     Created
 ✔ Container idm-compose01-mail-1   Created
 ✔ Container idm-compose01-iman-1   Created
 ✔ Container idm-compose01-idcon-1  Created
 ✔ Container idm-compose01-rl-1     Created
 ✔ Container idm-compose01-idv-1    Created
 ✔ Container idm-compose01-osp-1    Created
 ✔ Container idm-compose01-apps-1   Created
 ✔ Container idm-compose01-sspr-1   Created
 ✔ Container idm-compose01-forms-1  Created
[+] Copying 1/1
 ✔ idm-compose01-apps-1 copy ./config to idm-compose01-apps-1:/ Copied
[+] Copying 1/1
 ✔ idm-compose01-db-1 copy ./config/data/init.sql to idm-compose01-db-1:/docker-entrypoint-initdb.d/ Cop...
[+] Running 1/1
 ✔ Container idm-compose01-db-1  Started
[+] Running 1/1
 ✔ Container idm-compose01-iman-1  Started
[+] Running 1/1
 ✔ Container idm-compose01-mail-1  Started
[+] Running 1/1
 ✔ Container idm-compose01-rl-1  Started
INFO: You can follow the init progess in more detail by running  idm-compose logs -f  in a second terminal
[+] Running 1/1
 ✔ Container idm-compose01-idv-1  Started
Waiting for Edirectory to initialize............................................................. Done
[+] Copying 1/1
 ✔ idm-compose01-idv-1 copy idm-compose01-idv-1:/config/idm/eDirectory_data/data/SSCert.pem to . Copied
Adding symlink  '/config/data/SSCert.pem' -> '/config/idm/eDirectory_data/data/SSCert.pem'
[+] Restarting 1/1
 ✔ Container idm-compose01-idcon-1  Started
[+] Restarting 1/1
 ✔ Container idm-compose01-osp-1  Started
Waiting for OSP to initialize................... Done
Importing tree CA into OSP keystores
Certificate was added to keystore
Importing keystore /config/osp/tomcat/conf/tomcat.ks to /config/osp/tomcat/conf/idm.jks...
Entry for alias tomcat successfully imported.
Warning: Overwriting existing alias idm-local_ca in destination keystore
Entry for alias idm-local_ca successfully imported.
Entry for alias idm-compose01_ca successfully imported.
Import command completed:  3 entries successfully imported, 0 entries failed or cancelled
Importing keystore /config/osp/tomcat/conf/tomcat.ks to /opt/netiq/common/jre/lib/security/cacerts...
Entry for alias tomcat successfully imported.
Entry for alias idm-local_ca successfully imported.
Entry for alias idm-compose01_ca successfully imported.
Import command completed:  3 entries successfully imported, 0 entries failed or cancelled
[+] Restarting 1/1
 ✔ Container idm-compose01-osp-1  Started
Waiting for OSP to restart............ Done
[+] Restarting 1/1
 ✔ Container idm-compose01-apps-1  Started
Waiting for User App to initialize.......................................
Importing keystore /config/userapp/tomcat/conf/tomcat.ks to /config/userapp/tomcat/conf/idm.jks...
Entry for alias tomcat successfully imported.
Warning: Overwriting existing alias idm-local_ca in destination keystore
Entry for alias idm-local_ca successfully imported.
Import command completed:  2 entries successfully imported, 0 entries failed or cancelled
Importing keystore /config/userapp/tomcat/conf/tomcat.ks to /opt/netiq/common/jre/lib/security/cacerts...
Entry for alias tomcat successfully imported.
Entry for alias idm-local_ca successfully imported.
Import command completed:  2 entries successfully imported, 0 entries failed or cancelled
............................................ Done
[+] Restarting 1/1
 ✔ Container idm-compose01-apps-1  Started
[+] Restarting 1/1p (this may take a few minutes to complete)
 ✔ Container idm-compose01-forms-1  Started
[+] Copying 1/1
 ✔ idm-compose01-sspr-1 copy ./config/data/ to idm-compose01-sspr-1:/config/ Copied
[+] Copying 1/1
 ✔ idm-compose01-sspr-1 copy ./config/silent.properties to idm-compose01-sspr-1:/config/ Copied
[+] Running 1/1
 ✔ Container idm-compose01-sspr-1  Started
Waiting for SSPR to initialize... Done
Zertifikat in Datei <ca.der> gespeichert
Zertifikat in Datei <server.der> gespeichert
[+] Copying 1/1
 ✔ idm-compose01-sspr-1 copy config/data/SSPRConfiguration.xml to idm-compose01-sspr-1:/config/ Copied

The following services should soon be available for login as 'cn=admin,ou=sa,o=system' with password 'n0v3ll' (use NDAP format for iMonitor/iManager):

 ID Console ->	https://idcon.idm.local:1900/identityconsole
 LDAP       ->	ldap://idv.idm.local:1389
            ->	ldaps://idv.idm.local:1636
 iMonitor   ->	https://idv.idm.local:1828/nds
 iManager   ->	https://iman.idm.local:1843/nps
 WebMail    ->	https://mail.idm.local:1447

Use 'cn=appadmin,ou=sa,o=data' with password 'n0v3ll' to log in to:

 UserApp    ->	https://apps.idm.local:1443/idmdash
 SSPR       ->	https://sspr.idm.local:1445/sspr

Make sure to import <path to idm-compose>/ca.crt as a trusted root CA certificate into your browser and add the following lines to /etc/hosts on your Docker host:

127.0.0.1	apps.idm.local
127.0.0.1	db.idm.local
127.0.0.1	forms.idm.local
127.0.0.1	idcon.idm.local
127.0.0.1	idv.idm.local
127.0.0.1	iman.idm.local
127.0.0.1	mail.idm.local
127.0.0.1	osp.idm.local
127.0.0.1	rl.idm.local
127.0.0.1	sspr.idm.local

Designer requires a NAT mapping from the internal address 172.77.1.2:1636 to 127.0.0.1:1636 to properly connect to the new tree (in Window > Preferences > NetIQ > Identity Manager > NAT Mapping).

The Edirectory CA certificate for the IDM-COMPOSE01 tree can be found at <path to idm-compose>/SSCert.pem to validate LDAP and iMonitor connections.
```
