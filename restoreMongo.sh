#!/bin/bash

cancel(){
	echo "$1"
    exit 127
}

cat << EOF 


  __  __    ___    _  _    ___    ___      ___   ___   ___   _____    ___    ___   ___ 
 |  \/  |  / _ \  | \| |  / __|  / _ \    | _ \ | __| / __| |_   _|  / _ \  | _ \ | __|
 | |\/| | | (_) | |    | | (_ | | (_) |   |   / | _|  \__ \   | |   | (_) | |   / | _| 
 |_|  |_|  \___/  |_|\_|  \___|  \___/    |_|_\ |___| |___/   |_|    \___/  |_|_\ |___|
                -----------------------------------------------------                                                                      
EOF

. /root/.profile

S3_ROOT="s3://${BUCKET_URL}/backups/${PROJECT}/${DEFAULT_BACKUP_DIR}/"

DATE=$(date +%Y%m%d-%H%M)
COMPTEUR_TASK=1
SUMMARY_TABLE="+---+--------------------------------------------------------------+--------------------------------------------------------------+"
SUMMARY_TABLE="${SUMMARY_TABLE}\n|///|\t\t\t               R E M O T E L Y\t\t\t                               \t\t\t                L O C A L L Y  \t\t\t\t "
	

# DISPLAY DATABASE PRESENT LOCALLY
echo ""
echo "******************************************************"
echo "*                                                    *"
echo "* D A T A B A S E   D E T E C T E D   L O C A L L Y  *"
echo "*                                                    *"
echo "******************************************************"
echo 'show dbs' | ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} --quiet
echo ""


# AND DISPLAY BACKUP PRESENT ON BUCKET
echo ""
echo "******************************************************"
echo "*                                                    *"
echo "*   R E M O T E   B A C K U P   A V A I L A B L E    *"
echo "*                                                    *"
echo "******************************************************"
/usr/bin/s3cmd ls s3://${BUCKET_URL}/backups/${PROJECT}/${DEFAULT_BACKUP_DIR}/
listing=$(/usr/bin/s3cmd ls s3://${BUCKET_URL}/backups/${PROJECT}/${DEFAULT_BACKUP_DIR}/)
echo ""

last=$(echo ${listing} | rev | cut -d '/' -f 1 | rev)
if [ ! -n "${last}" ];  then 	cancel "No backup found on S3. Operation canceled !"	  ; fi


# CHOOSE BACKUP
echo "Choose the backup you want to apply : [${last}]"; read -p "${S3_ROOT}" yn
if [ ! -n "${yn}" ];  then 	yn=${last}	  ; fi

/usr/bin/s3cmd get --force s3://${BUCKET_URL}/backups/${PROJECT}/${DEFAULT_BACKUP_DIR}/${yn} /tmp/restore.tar.gz
if [ ! $? -eq 0 ]; then cancel "Cannot download file ${yn}. Operation canceled! ";fi

cd /tmp
tar xvzf /tmp/restore.tar.gz > /dev/null

if [ ! $? -eq 0 ]; then cancel "Cannot untar file ${yn}. Operation canceled! " ; fi
cd -
NAME=${yn%.*.*}
ls -l /tmp/data/backups/${DEFAULT_BACKUP_DIR}/${NAME}/${schema}/


echo "Select one schema for restoration : [${DB_NAME}] : "; read -p "" schema

if [ ! -n "${schema}" ]; then
	schema=${DB_NAME}
fi

echo "Select database name after restoration ? [${DB_NAME}] : "; read -p "" dbName

if [ ! -n "${dbName}" ]; then
	dbName=${DB_NAME}
fi

DB_EXIST=$(echo 'show dbs' | ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} --quiet | cut -d " " -f 1 | grep "^${dbName}$")

if [ -n "${DB_EXIST}" ]; then
	SUMMARY_TABLE="${SUMMARY_TABLE}\n+---+--------------------------------------------------------------+--------------------------------------------------------------+"
	SUMMARY_TABLE="${SUMMARY_TABLE}\n| ${COMPTEUR_TASK} | \t\t\t\t\t\t\t\t\t                                              ${dbName} => ${dbName}_${DATE} "
    COMPTEUR_TASK=$((COMPTEUR_TASK+1))
    DB_NAME_TMP=${dbName}_restore
else
	DB_NAME_TMP=${dbName}
fi

SUMMARY_TABLE="${SUMMARY_TABLE}\n+---+--------------------------------------------------------------+--------------------------------------------------------------+"
SUMMARY_TABLE="${SUMMARY_TABLE}\n| ${COMPTEUR_TASK} |   Backup (${NAME}/${schema}) => ${dbName} "
COMPTEUR_TASK=$((COMPTEUR_TASK+1))

if [ -n "${DB_EXIST}" ]; then
	echo "By default, your old database will be copied into a temporary database named ${dbName}_${DATE}. Do you want to delete it after restoration ? [y/N] : "; read -p "" deleteDB

	case "$deleteDB" in
	    [yY]) 
			SUMMARY_TABLE="${SUMMARY_TABLE}\n+---+--------------------------------------------------------------+--------------------------------------------------------------+"
			SUMMARY_TABLE="${SUMMARY_TABLE}\n| ${COMPTEUR_TASK} | \t\t\t\t\t\t\t\t\t                                              ${dbName}_${DATE} => D E L E T E D"
	     	COMPTEUR_TASK=$((COMPTEUR_TASK+1))
	     ;; 
		*)  deleteDB="N" 
		;;
	esac
else
	SUMMARY_TABLE="${SUMMARY_TABLE}\n+---+--------------------------------------------------------------+--------------------------------------------------------------+"
	SUMMARY_TABLE="${SUMMARY_TABLE}\n|///| \t\t\t\t\t\t\t\t\t                                              Adding right for ${DB_NAME_TMP}"
	SUMMARY_TABLE="${SUMMARY_TABLE}\n| ${COMPTEUR_TASK} | \t\t\t\t\t\t\t\t\t                                              user: \"${DB_USER}\" "
	SUMMARY_TABLE="${SUMMARY_TABLE}\n|///| \t\t\t\t\t\t\t\t\t                                              pwd: \"${DB_PWD}\" "
 	COMPTEUR_TASK=$((COMPTEUR_TASK+1))
	deleteDB="y" 
fi

SUMMARY_TABLE="${SUMMARY_TABLE}\n+---+--------------------------------------------------------------+--------------------------------------------------------------+"


cat << EOF 
	  ___   _   _   __  __   __  __     _     ___  __   __
	 / __| | | | | |  \/  | |  \/  |   /_\   | _ \ \ \ / /
	 \__ \ | |_| | | |\/| | | |\/| |  / _ \  |   /  \ V / 
	 |___/  \___/  |_|  |_| |_|  |_| /_/ \_\ |_|_\   |_|  
	                                                     
EOF

echo $SUMMARY_TABLE

read -p "Do you agree with this parameters [y/N]" agreed

if [ ! -n "${agreed}" ];  then
	agreed="N"
fi

case "$agreed" in
    [yY]) 
		if [  -d /tmp/data/backups/${DEFAULT_BACKUP_DIR}/${NAME}/${schema}/ ]; then
	    	echo "Starting restoration for database ${dbName}"
	        ${MONGO_HOME}/bin/mongorestore ${MONGO_OPTS} -db ${DB_NAME_TMP} /tmp/data/backups/${DEFAULT_BACKUP_DIR}/${NAME}/${schema}/
	        if [ -n "${DB_EXIST}" ]; then
	        	echo "Saving current database ... that may take few minute depending db size."
		        ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} --eval "printjson(db.copyDatabase('${dbName}', '${dbName}_${DATE}'))" > /dev/null
		        if [ ! $? -eq 0 ]; then cancel "Failure when saving old database. Operation canceled! " ; fi
		        
		        echo "Droping current database ..."
		        ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} ${dbName} --eval "printjson(db.dropDatabase())" > /dev/null
		        
   		        echo "Restore choose database ..."
		        ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} --eval "printjson(db.copyDatabase('${DB_NAME_TMP}', '${dbName}'))" > /dev/null
		        ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} ${DB_NAME_TMP} --eval "printjson(db.dropDatabase())" > /dev/null

		       	case "$deleteDB" in
				    [yY])  ${MONGO_HOME}/bin/mongo ${MONGO_OPTS} ${dbName}_${DATE} --eval "printjson(db.dropDatabase())" > /dev/null ;;
					*) echo "Skipping deleting ! " ;;
				esac
			else
				echo "Adding right for new database"
				
				INSERT_STATEMENT="db.createUser({user: \"${DB_USER}\",pwd: \"${DB_PWD}\",roles: [{ role: \"readWrite\", db: \"${DB_NAME_TMP}\" }]})"
				echo "${INSERT_STATEMENT}" | ${MONGO_HOME}/bin/mongo  ${MONGO_OPTS} ${DB_NAME_TMP} > /dev/null	


			fi
	        rm /tmp/restore.tar.gz
	        rm -rf /tmp/data/
	   
	    else 
	    	cancel "No repository name find (/tmp/data/backups/${DEFAULT_BACKUP_DIR}/${NAME}/${schema}/). Cannot restore this schema. Operation canceled !"
	    fi 

	;; 
	*)  cancel "Operation canceled ! ";;
esac



