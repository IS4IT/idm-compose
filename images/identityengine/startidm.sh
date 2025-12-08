#!/bin/sh

echo "Running /startidm.sh ..."
source /opt/novell/eDirectory/bin/ndspath

trap '/opt/novell/eDirectory/bin/ndsmanage stopall && exit 0' SIGTERM
if [ ! -z "$debug" ] && [ "$debug" = 'y' ]
then
	set -x
	calldebug="bash -x"
fi

waitForPKIServerSelfProvisioning()
{
	loop=true
	if [ -f /var/opt/novell/eDirectory/log/PKIHealth.log ]
	then
		echo "Waiting for the PKI server self-provisioning to complete"
		while $loop
		do
			grep -i "Step 8 succeeded" /var/opt/novell/eDirectory/log/PKIHealth.log &> /dev/null
			if [ $? -eq 0 ]
			then
				echo "PKI server self-provisioning completed"
				loop=false
				break
			else
				sleep 20s
			fi
		done
	fi
}


runNDSRepair()
{
	if [ ! -f /sharedconfig/hosts.nds ]
	then
	    echo "$ID_VAULT_SERVERNAME $ID_VAULT_POD_IP"  > /sharedconfig/hosts.nds
	else
        if grep -q $ID_VAULT_SERVERNAME /sharedconfig/hosts.nds
		then
            sed -i "/$ID_VAULT_SERVERNAME/c\\$ID_VAULT_SERVERNAME $ID_VAULT_POD_IP" /sharedconfig/hosts.nds
        else
            echo "$ID_VAULT_SERVERNAME $ID_VAULT_POD_IP"  >> /sharedconfig/hosts.nds
        fi 
	fi

	cp -rf /sharedconfig/hosts.nds /etc/opt/novell/eDirectory/conf/hosts.nds
	su -l nds -c "printf '1\n1' | CONTAINER_MODE=1 NDS_DOCKER_BUILD=1 ndsrepair -N"

}

enablePKIServerSelfProvisioning()
{

    local ldif_file=/idm/IDM/ldif/enable_server_self_provisioning.ldif
	sed -i s/__ID_VAULT_TREENAME__/$ID_VAULT_TREENAME/g $ldif_file

	/opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar com.netiq.installer.utils.ImportCertificate -src ${ID_VAULT_HOST}:${ID_VAULT_LDAPS_PORT} -ks /opt/netiq/common/jre/lib/security/cacerts -pwd "changeit" -a temppkiserver

    echo "Enabling PKI Server Self Provisioning "
	
	/opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar:/idm/common/lib/ldap.jar com.netiq.installer.utils.LdiffImport $ID_VAULT_HOST $ID_VAULT_LDAPS_PORT "$ID_VAULT_ADMIN_LDAP" "${ID_VAULT_PASSWORD}" /opt/netiq/common/jre/lib/security/cacerts "changeit" "$ldif_file" /dev/null 

	/opt/netiq/common/jre/bin/keytool -delete -noprompt -alias temppkiserver -keystore /opt/netiq/common/jre/lib/security/cacerts -storepass changeit
}

addSecondaryServerRightsToCA()
{
    SERVER_NCP_DN=$(su -l nds -c "ndsstat" | grep "Server Name:")
    IFS='.' read -ra ARR <<< "$SERVER_NCP_DN"
    SERVER_LDAP_DN=${ARR[1]}
    for (( i=2;  i < ${#ARR[@]} - 1 ;  i++ ))
    do
        SERVER_LDAP_DN=${SERVER_LDAP_DN},${ARR[i]} 
    done

    local ldif_file=/idm/IDM/ldif/secondary_server_rights.ldif
    sed -i s/__ID_VAULT_TREENAME__/$ID_VAULT_TREENAME/g $ldif_file
    sed -i s/__ID_VAULT_SERVER_LDAP_DN__/$SERVER_LDAP_DN/g $ldif_file

    /opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar com.netiq.installer.utils.ImportCertificate -src ${ID_VAULT_HOST}:${ID_VAULT_LDAPS_PORT} -ks /opt/netiq/common/jre/lib/security/cacerts -pwd "changeit" -a temppkiserver

    echo "Adding Entry and All Attributes Rights to CA Object"
	
    /opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar:/idm/common/lib/ldap.jar com.netiq.installer.utils.LdiffImport $ID_VAULT_HOST $ID_VAULT_LDAPS_PORT "$ID_VAULT_ADMIN_LDAP" "${ID_VAULT_PASSWORD}" /opt/netiq/common/jre/lib/security/cacerts "changeit" "$ldif_file" /dev/null 

    /opt/netiq/common/jre/bin/keytool -delete -noprompt -alias temppkiserver -keystore /opt/netiq/common/jre/lib/security/cacerts -storepass changeit
}

waitForEdirStart()
{
	TEMP_LOG_FILE_NAME=/tmp/temporary.log
    
	echo "Waiting for eDirectory to start ..."

	# Wait for LDAP Connection
	while true
    do
        /opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar:/idm/common/lib/ldap.jar com.netiq.installer.utils.VerifyLDAPConnection $ID_VAULT_HOST $ID_VAULT_LDAPS_PORT "$ID_VAULT_ADMIN_LDAP" "$ID_VAULT_PASSWORD" ${TEMP_LOG_FILE_NAME} &>/dev/null
        RET=$?
	    if (( $RET == 0 )); then
	        echo "eDirectory LDAP Server is running"
			break
	    fi
		sleep 10
	done
    
	# Wait for NCP Connection
	while true
    do
        su -l nds -c "ndsstat &> /dev/null"
		RET=$?
	    if (( $RET == 0 )); then
	        echo "eDirectory NCP Server is running"
			sleep 20
			break
	    fi
		sleep 10
	done

}


schemaExtend()
{
        SCHEMADIR=/opt/novell/eDirectory/lib/nds-schema
		#EDIR_SCHEMA_FILES=$(ls $SCHEMADIR/*.sch)
		# Add the new schema files only in proper order otherwise schema will not be extended.
		#
		# Order of execution in schema file is crucial
		#
        EDIR_SCHEMA_FILES="vrschema.sch dvr_ext.sch sap.sch sapuser.sch nsimAux.sch WkOdrDvr.sch nxdrv.sch i5os.sch racf.sch tss.sch fanout.sch srvprv.sch nrf-extensions.sch osp.sch authsaml.sch edirectory-schema.sch blackboard.sch Banner.sch pum.sch acf2.sch Novell_Google_Schema.sch notf.sch wd-schema.sch scim-schema.sch pdsEpicUser.sch sapHana-schema.sch"
		if [ "$TREE_CONFIG" == "existingtreeremote" ]
		then
			if [ -z "$ID_VAULT_TREENAME" ] || [ -z "${ID_VAULT_EXISTING_SERVER}" ] || [ -z "${ID_VAULT_EXISTING_NCP_PORT}" ]
			then
				echo "one of ID_VAULT_TREENAME/ID_VAULT_EXISTING_SERVER/ID_VAULT_EXISTING_NCP_PORT undefined"
				echo "Exiting..."
				kill 1
				exit 1
			fi
		fi
		if [ "$TREE_CONFIG" == "existingtreeremote" ]
		then
			su -l nds -c "ldapconfig set \"Require TLS for Simple Binds with Password=no\" -a $ID_VAULT_ADMIN -w \"${ID_VAULT_PASSWORD}\" -t $ID_VAULT_TREENAME -p ${ID_VAULT_EXISTING_SERVER}:${ID_VAULT_EXISTING_NCP_PORT} > /dev/null 2>&1"
		else
			su -l nds -c "ldapconfig set \"Require TLS for Simple Binds with Password=no\" -a $ID_VAULT_ADMIN -w \"${ID_VAULT_PASSWORD}\" > /dev/null 2>&1"
		fi
		for SCH in $EDIR_SCHEMA_FILES
                do
		  	if [ ! -f $SCHEMADIR/$SCH ]
		  	then
		    		continue
		  	fi
		  	str=`gettext install "Extending Identity Manager schema"`
		  	echo "$str $SCHEMADIR/$SCH." > /dev/null 2>&1
		  	RC=0
		  	if [ "$TREE_CONFIG" == "existingtreeremote" ]
		  	then
               			su -l nds -c "source /opt/novell/eDirectory/bin/ndspath 1> /dev/null 2>&1; /opt/novell/eDirectory/bin/ndssch -h ${ID_VAULT_EXISTING_SERVER}:${ID_VAULT_EXISTING_NCP_PORT} -t $ID_VAULT_TREENAME $ID_VAULT_ADMIN $SCHEMADIR/$SCH -p \"${ID_VAULT_PASSWORD}\" > /dev/null 2>&1"
	       			RC=$?
		  	else
               		su -l nds -c "source /opt/novell/eDirectory/bin/ndspath 1> /dev/null 2>&1;export DISABLE_EBA=true;/opt/novell/eDirectory/bin/ndssch -t $TREENAME $ID_VAULT_ADMIN $SCHEMADIR/$SCH -p \"${ID_VAULT_PASSWORD}\" > /dev/null 2>&1"
	       			RC=$?
		  	fi
	       		if [ $RC -ne 0 ]
	       		then
	        		echo "Error $RC while configuring schema $SCHEMADIR/$SCH"
				echo "Exiting..."
				#kill 1
				#exit 1
	       		fi	
                done
		if [ "$TREE_CONFIG" == "existingtreeremote" ]
		then
			su -l nds -c "ldapconfig set \"Require TLS for Simple Binds with Password=yes\" -a $ID_VAULT_ADMIN -w \"${ID_VAULT_PASSWORD}\" -t $ID_VAULT_TREENAME -p ${ID_VAULT_EXISTING_SERVER}:${ID_VAULT_EXISTING_NCP_PORT} > /dev/null 2>&1"
		else
			su -l nds -c "ldapconfig set \"Require TLS for Simple Binds with Password=yes\" -a $ID_VAULT_ADMIN -w \"${ID_VAULT_PASSWORD}\" > /dev/null 2>&1"
		fi
} 

if [[ $VOLUME_CONFIGURED -eq 0 ]]
then
	cd /idm
	/bin/sh /nici-postinstall.sh &> /dev/null
	/var/opt/novell/nici/set_server_mode64 &> /dev/null
	chown -R nds:nds /config/idm /tmp /dev
	if [ -z ${SILENT_INSTALL_FILE} ] && [ -z ${VALUES_YAML_PATH} ] && [ -z ${INSTALL_ENGINE} ]
	then
		echo "Interactive install not supported. Exiting..."
		kill 1
		exit 1
		su -l nds -c "cd /idm ;debug=$debug DOCKER_CONTAINER=y $calldebug ./configure.sh"
	else
		if [ ! -z ${INSTALL_ENGINE} ]
		then
			timestamp=`date +"%Y%m%d%H%M%S"`
			SILENT_INSTALL_FILE=/tmp/silent-${timestamp}.properties
			env > ${SILENT_INSTALL_FILE}
		fi
		if [ ! -z ${SECRET_PROPERTY_PATH} ] && [ -f ${SECRET_PROPERTY_PATH} ]
		then
			cat ${SECRET_PROPERTY_PATH} >> ${SILENT_INSTALL_FILE}
		fi
		chown nds:nds ${SILENT_INSTALL_FILE}
		source ${SILENT_INSTALL_FILE}

	    if [ -z $ID_VAULT_ADMIN ] && [ ! -z $ID_VAULT_ADMIN_LDAP ]
		then
		    ID_VAULT_ADMIN="`/opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar com.netiq.installer.utils.ConvertDotNotation ${ID_VAULT_ADMIN_LDAP}`"
		    echo -e "\nID_VAULT_ADMIN=\"$ID_VAULT_ADMIN\"" >> "${SILENT_INSTALL_FILE}"
		fi

		if [ -z $ID_VAULT_ADMIN ] || [ -z $ID_VAULT_PASSWORD ] || [ -z $ID_VAULT_SERVERNAME ]
		then
			#Have to exit here
			echo ""
			echo "One/All of ID_VAULT_ADMIN(dot format), ID_VAULT_PASSWORD or ID_VAULT_SERVERNAME are not defined"
			echo "Exiting..."
			echo ""
			kill 1
			exit 1
		fi

		if [ ! -z ${ID_VAULT_EXISTING_HEALTH_CHECK_PORT} ]; then
		  if [ "$TREE_CONFIG" == "existingtreeremote" ]
		  then
      		until nc -z $ID_VAULT_EXISTING_SERVER $ID_VAULT_EXISTING_HEALTH_CHECK_PORT > /dev/null; do echo Waiting for the Primary Engine Server to start...; sleep 20; done; 2>&1
		  fi
		fi


		if [ ! -z "$debug" ] && [ "$debug" = 'y' ]
		then
		su -l nds -c "cd /idm; debug=$debug DOCKER_CONTAINER=y $calldebug ./configure.sh -s -ssc -slc -f ${SILENT_INSTALL_FILE}"
		else
		su -l nds -c "cd /idm; debug=$debug DOCKER_CONTAINER=y $calldebug ./configure.sh -s -ssc -slc -f ${SILENT_INSTALL_FILE}" &> /dev/null
		fi

        if [ ! -z ${KUBERNETES_ORCHESTRATION} ] && [ "${KUBERNETES_ORCHESTRATION}" == "y" ]; then
		
            waitForEdirStart
            if [ "${TREE_CONFIG}" == "newtree" ] 
            then
                enablePKIServerSelfProvisioning 
            else
                addSecondaryServerRightsToCA    
            fi
        fi

	fi
	su -l nds -c "yes|cp /idm/version.properties /config/idm/" &> /dev/null
	#cat /var/opt/novell/eDirectory/log/ndsd.log
else
	if [ ! -z ${INSTALL_ENGINE} ]
	then
		timestamp=`date +"%Y%m%d%H%M%S"`
		SILENT_INSTALL_FILE=/tmp/silent-${timestamp}.properties
		env > ${SILENT_INSTALL_FILE}
	fi
	if [ ! -z ${SILENT_INSTALL_FILE} ]
	then
		if [ ! -z ${SECRET_PROPERTY_PATH} ] && [ -f ${SECRET_PROPERTY_PATH} ]
		then
			cat ${SECRET_PROPERTY_PATH} >> ${SILENT_INSTALL_FILE}
		fi
		[ -f ${SILENT_INSTALL_FILE} ] && source ${SILENT_INSTALL_FILE}

	    if [ -z $ID_VAULT_ADMIN ] && [ ! -z $ID_VAULT_ADMIN_LDAP ]
		then
		    ID_VAULT_ADMIN="`/opt/netiq/common/jre/bin/java -cp /idm/common/packages/utils/idm_install_utils.jar com.netiq.installer.utils.ConvertDotNotation ${ID_VAULT_ADMIN_LDAP}`"
		    echo -e "\nID_VAULT_ADMIN=\"$ID_VAULT_ADMIN\"" >> "${SILENT_INSTALL_FILE}"
		fi

	fi
	#Need to do check existing version
	echo "Starting eDirectory" 
	su -l nds -c "/opt/novell/eDirectory/bin/ndsmanage startall"
	NDSCONFFILE=$(su -l nds -c "/opt/novell/eDirectory/bin/ndsstat" | grep Instance | sed -n 1p | cut -d"/" -f2- | cut -d":" -f1)
	NDSCONFFILE=$(echo /$NDSCONFFILE)
	TREENAME="$(su -l nds -c "/opt/novell/eDirectory/bin/ndsstat" | grep "Tree Name" | sed -n 1p | cut -d":" -f2 | cut -d" " -f2-)"
    RUNNING_IDM_VERSION=$(grep novell-DXMLengnx /config/idm/version.properties | cut -d"-" -f3)
	if [ -f /idmpatch/common/scripts/common_install_vars.sh ]
	then
		source /idmpatch/common/scripts/common_install_vars.sh
	else
		source /idm/common/scripts/common_install_vars.sh
	fi
	IMAGE_IDM_VERSION=$(grep novell-DXMLengnx /idm/version.properties | cut -d"-" -f3)
	if [ "$RUNNING_IDM_VERSION" == "$IMAGE_IDM_VERSION" ]
	then
		echo "Proceeding" 
	else
		if [ -z $ID_VAULT_ADMIN ] || [ -z $ID_VAULT_PASSWORD ] 
		then
			#Have to exit here
			echo ""
			echo "One of ID_VAULT_ADMIN(dot format) or ID_VAULT_PASSWORD are not defined"
			echo "Exiting..."
			echo ""
			kill 1
			exit 1
		fi
		echo "Using silent install file ${SILENT_INSTALL_FILE}"
		if [ ! -z ${SILENT_INSTALL_FILE} ]
		then
		  su -l nds -c "export DISABLE_EBA=true; source ${SILENT_INSTALL_FILE} & /opt/novell/eDirectory/bin/ndslogin --config-file $NDSCONFFILE "$ID_VAULT_ADMIN" -p "$ID_VAULT_PASSWORD" &> /dev/null"
	    else	
		  su -l nds -c "export DISABLE_EBA=true; /opt/novell/eDirectory/bin/ndslogin -t "$TREENAME" "$ID_VAULT_ADMIN" -p "$ID_VAULT_PASSWORD" &> /dev/null"
		fi
		if [ $? -ne 0 ]
		then
			# ndslogin failed - exiting
			echo ""
			echo "User credentials are invalid"
			echo "Exiting..."
			echo ""
			echo "Stopping eDirectory"
			su -l nds -c "/opt/novell/eDirectory/bin/ndsmanage stopall"
			kill 1
			exit 1
		fi
		printf "$RUNNING_IDM_VERSION\n$SUPPORTED_DOCKER_IDM_VERSION" | sort -V | sed -n '1p' | grep -q $RUNNING_IDM_VERSION
		MIN_SUPPORTED_VERSION=$?
		if [ $MIN_SUPPORTED_VERSION -eq 0 ] && [ "$RUNNING_IDM_VERSION" != "$SUPPORTED_DOCKER_IDM_VERSION" ]
		then
			# Have to exit since lowest among running version and supported is running version
			echo ""
			echo "Minimum supported IDM version is $SUPPORTED_DOCKER_IDM_VERSION"
			echo ""
			echo "Start the container with $SUPPORTED_DOCKER_IDM_VERSION first and then can be started with $IMAGE_IDM_VERSION"
			echo "Exiting..."
			echo ""
			echo "Stopping eDirectory"
			su -l nds -c "/opt/novell/eDirectory/bin/ndsmanage stopall"
			kill 1
			exit 1
		fi
		# If say we try to start the container with older version compared to the data layer; it should exit
		printf "$RUNNING_IDM_VERSION\n$IMAGE_IDM_VERSION" | sort -V | sed -n '1p' | grep -q $RUNNING_IDM_VERSION
		CORRECT_IDM_VERION_TOPROCEED=$?
		if [ $CORRECT_IDM_VERION_TOPROCEED -ne 0 ]
		then
			# As per ordering running version should be the first; if not exit
			echo ""
			echo "Configured data layer has been run with a version later than $IMAGE_IDM_VERSION"
			echo "Exiting..."
			echo ""
			kill 1
			exit 1
		fi
		# At this stage running and supported could be same or running could be smaller; either way now it could be upgraded
		# Running ndsconfig upgrade
		su -l nds -c "export DISABLE_EBA=true;/opt/novell/eDirectory/bin/ndsconfig upgrade -j  -a "$ID_VAULT_ADMIN" -w "$ID_VAULT_PASSWORD" --config-file $NDSCONFFILE"
		if [ $? -ne 0 ]
		then
			echo ""
			echo "Upgrade of eDirectory failed"
			echo "Exiting..."
			echo ""
			echo "Stopping eDirectory"
			su -l nds -c "/opt/novell/eDirectory/bin/ndsmanage stopall"
			kill 1
			exit 1
		else
		    echo "Running new nmasupgrade utility from eDirectory 9.3"
			su -l nds -c "export DISABLE_EBA=true;/home/nds/eDirectory/nmas/nmasupgrade -a "$ID_VAULT_ADMIN" -w "$ID_VAULT_PASSWORD" --edir_binpath /home/nds/eDirectory --config-file $NDSCONFFILE"
		fi
		schemaExtend
	fi
	#At the end copy the image rpm version
	su -l nds -c "yes|cp -v /idm/version.properties /config/idm/"
fi
if [ "$debug" = 'y' ]
then
	set +x
fi

#if [ -L /etc/opt/novell/eDirectory/conf/env_idm ]
#then
#        rm /etc/opt/novell/eDirectory/conf/env_idm
#fi

if [ -f $HOME/.bashrc ]
then
    if ! grep -q "source /opt/novell/eDirectory/bin/ndspath" $HOME/.bashrc
    then
        echo "source /opt/novell/eDirectory/bin/ndspath" >> $HOME/.bashrc
    fi
fi

echo "Press ctrl+p ctrl+q to continue. This would detach you from the container."
sleep 10s
DefaultLogFile="/var/opt/novell/eDirectory/log/ndsd.log"
LOGTOFOLLOWistrue=1

TLS_CERT_PATH=/config/idm/tls.crt
if [ ! -z ${KUBERNETES_ORCHESTRATION} ] && [ "${KUBERNETES_ORCHESTRATION}" == "y" ]; then
    TLS_CERT_PATH=$INGRESS_TLS_CERT_PATH
fi
if [ -f $TLS_CERT_PATH ]
then
	/opt/netiq/common/jre/bin/keytool -trustcacerts -keystore /opt/netiq/common/jre/lib/security/cacerts -storepass changeit -importcert -alias rootcertfromtlscrtfile -file $TLS_CERT_PATH -noprompt | grep "already exists" &> /dev/null
	if [ $? -eq 0 ]
	then
		#Deleting the alias first and then re-trying it again
		/opt/netiq/common/jre/bin/keytool -delete -noprompt -trustcacerts -alias rootcertfromtlscrtfile -keystore /opt/netiq/common/jre/lib/security/cacerts -storepass changeit &> /dev/null
		/opt/netiq/common/jre/bin/keytool -trustcacerts -keystore /opt/netiq/common/jre/lib/security/cacerts -storepass changeit -importcert -alias rootcertfromtlscrtfile -file $TLS_CERT_PATH -noprompt &> /dev/null
	fi
fi
if [ -f "$TLS_CERT_PATH" ]
then
    c=1
    awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c++} {print > "/tmp/cert" c ".pem"}' "$TLS_CERT_PATH"
    for cert in /tmp/cert*.pem
	do
        alias="tlschaincert$c"
        /opt/netiq/common/jre/bin/keytool -trustcacerts -keystore /opt/netiq/common/jre/lib/security/cacerts \
            -storepass changeit -importcert -alias "$alias" -file "$cert" -noprompt &> /dev/null
        if [ $? -ne 0 ]
		then
            echo "Error importing $cert with alias $alias"
        fi
        c=$((c+1))
    done
    rm -f /tmp/cert*.pem
fi
if [ -f "/shared/ingress-tls.crt" ]
then
    c=1
    awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c++} {print > "/tmp/cert" c ".pem"}' "/shared/ingress-tls.crt"
    for cert in /tmp/cert*.pem
	do
        alias="tlschaincertfromingress$c"
        /opt/netiq/common/jre/bin/keytool -trustcacerts -keystore /opt/netiq/common/jre/lib/security/cacerts \
            -storepass changeit -importcert -alias "$alias" -file "$cert" -noprompt &> /dev/null
        if [ $? -ne 0 ]
		then
            echo "Error importing $cert with alias $alias"
        fi
        c=$((c+1))
    done
    rm -f /tmp/cert*.pem
fi
if [ -d "/config/certificates" ]
then
    for pemfile in /config/certificates/*.pem
	do
        if [ -f "$pemfile" ]
		then
            c=1
            awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c++} {print > "/tmp/cert" c ".pem"}' "$pemfile"
            for cert in /tmp/cert*.pem
			do
                alias="tlschaincertfromcertdir${c}"
                /opt/netiq/common/jre/bin/keytool -trustcacerts -keystore /opt/netiq/common/jre/lib/security/cacerts \
                    -storepass changeit -importcert -alias "$alias" -file "$cert" -noprompt &> /dev/null
                if [ $? -ne 0 ]
				then
                    echo "Error importing $cert from $pemfile with alias $alias"
                fi
                c=$((c+1))
            done
            rm -f /tmp/cert*.pem
        fi
    done
fi
# Restarting ndsd
echo "Restarting eDirectory..."
su -l nds -c "CONTAINER_MODE=1 NDS_DOCKER_BUILD=1 /opt/novell/eDirectory/bin/ndsmanage stopall"
su -l nds -c "CONTAINER_MODE=1 NDS_DOCKER_BUILD=1 /opt/novell/eDirectory/bin/ndsmanage startall"

if [ ! -z ${KUBERNETES_ORCHESTRATION} ] && [ "${KUBERNETES_ORCHESTRATION}" == "y" ]; then
    waitForEdirStart
    if [[ $VOLUME_CONFIGURED -eq 1 ]]
    then
    	waitForPKIServerSelfProvisioning
    fi
    runNDSRepair
fi

if [ ! -z ${ID_VAULT_HEALTH_CHECK_PORT} ]; then
    # Mark the POD as ready to accept the traffic
    /opt/netiq/common/jre/bin/java -cp "/idmpatch/idm-containers-utils/*"  com.netiq.idm.install.idvault.Readiness $ID_VAULT_HEALTH_CHECK_PORT > /config/idm/log/healthcheck.log 2>&1 &
fi
rm -rf /idm/common/lib &> /dev/null

if [ ! -z "$LOGTOFOLLOW" ] && [ "$LOGTOFOLLOW" != "" ]
then
	ls $LOGTOFOLLOW &> /dev/null
	LOGTOFOLLOWistrue=$?
fi
if [ $LOGTOFOLLOWistrue -eq 0 ]
then
	tail -f $LOGTOFOLLOW
else
	tail -f $DefaultLogFile
fi
tail -f /dev/null
#while true; do :; done
