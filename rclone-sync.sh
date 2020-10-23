#!/bin/sh

rclone_exec() {
  CMD="rclone $RCLONE_CMD '${SYNC_SRC}' '${SYNC_DEST}' ${RCLONE_OPTS} ${SYNC_OPTS_ALL}"

  if [ ! -z "$LOG_ENABLED" ]
  then
    d=$(date +%Y_%m_%d-%H_%M_%S)
    LOG_FILE="${LOG_DIR}/rclone-$d.log"
    CMD="${CMD} --log-file=${LOG_FILE}"
  fi

  echo "INFO: Starting ${CMD}"
  set +e
  eval ${CMD}
  export RETURN_CODE=$?
  set -e
}

set -e

SYNC_DEST=/data
PID_FILE=/var/lib/rclone/rclone-sync.pid
LOG_DIR=/var/log/rclone

echo "INFO: Starting sync.sh pid $$ $(date)"

if [ `lsof | grep $0 | wc -l | tr -d ' '` -gt 1 ]
then
  echo "WARNING: A previous $RCLONE_CMD is still running. Skipping new $RCLONE_CMD command."
else

  # Signal start oh sync.sh to healthchecks.io
  if [ ! -z "${HEALTHCHECKS_IO_URL}" ]
  then
    echo "INFO: Sending start signal to healthchecks.io"
    wget ${HEALTHCHECKS_IO_URL}/start -O /dev/null
  fi

  # Delete logs by user request
  if [ ! -z "${ROTATE_LOG##*[!0-9]*}" ]
  then
    echo "INFO: Removing logs older than $ROTATE_LOG day(s)..."
    touch ${LOG_DIR}/tmp.log && find ${LOG_DIR}/*.log -mtime +$ROTATE_LOG -type f -delete && rm -f ${LOG_DIR}/tmp.log
  fi

  echo $$ > ${PID_FILE}

  # Evaluate any sync options
  if [ ! -z "$SYNC_OPTS_EVAL" ]
  then
    SYNC_OPTS_EVALUALTED=$(eval echo $SYNC_OPTS_EVAL)
    echo "INFO: Evaluated SYNC_OPTS_EVAL to: ${SYNC_OPTS_EVALUALTED}"
    SYNC_OPTS_ALL="${SYNC_OPTS} ${SYNC_OPTS_EVALUALTED}"
  else
    SYNC_OPTS_ALL="${SYNC_OPTS}"
  fi

  if [ ! -z "$RCLONE_DIR_CHECK_SKIP" ]
  then
    echo "INFO: Skipping source directory check..."

    rclone_exec
  else
    set e+
    if test "$(rclone --max-depth $RCLONE_DIR_CMD_DEPTH $RCLONE_DIR_CMD "$(eval echo $SYNC_SRC)" $RCLONE_OPTS)";
    then
      set e-
      echo "INFO: Source directory is not empty and can be processed without clear loss of data"

      rclone_exec
    else
      echo "WARNING: Source directory is empty. Skipping $RCLONE_CMD command."
    fi
  fi

  # Wrap up healthchecks.io call with complete or failure signal
  if [ ! -z "${HEALTHCHECKS_IO_URL}" ]
  then
    if [ "$RETURN_CODE" == 0 ]
    then
      echo "INFO: Sending complete signal to healthchecks.io"
      wget ${HEALTHCHECKS_IO_URL} -O /dev/null
    else
      echo "WARNING: Sending failure signal to healthchecks.io"
      wget ${HEALTHCHECKS_IO_URL}/fail -O /dev/null
    fi
  fi

  rm -f ${PID_FILE}
fi
