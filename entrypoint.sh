#!/bin/bash

set -e

# Announce version
echo "INFO: Running $(rclone --version | head -n 1)"

if [[ ! ${RCLONE_CMD} =~ (copy|move|sync) ]]; then
  echo "WARNING: rclone command '${RCLONE_CMD}' is not supported by this container, please use sync/copy/move. Stopping."
  exit 1
else if [[ ! ${RCLONE_DIR_CMD} =~ (ls|lsf) ]]; then
  echo "WARNING: rclone directory command '${RCLONE_DIR_CMD}' is not supported by this container, please use ls/lsf. Stopping."
  exit 1
else if [ -z "$GID" -a ! -z "$UID" ] || [ -z "$UID" -a ! -z "$GID" ]; then
  echo "WARNING: Must supply both UID and GID or neither. Stopping."
  exit 1
else if [ ! -z "$TZ" -a -f /usr/share/zoneinfo/$TZ ]; then
  echo "WARNING: TZ was set '${TZ}', but corresponding zoneinfo file does not exist. Stopping."
  exit 1
fi

if [ -z "$UID" ]
then
  USER=$(whoami)
else
  USER=$(getent passwd "$UID" | cut -d: -f1)
  GROUP=$(getent group "$GID" | cut -d: -f1)

  if [ -z "$GROUP" ]
  then
    GROUP=rclone
    addgroup --gid "$GID" "$GROUP"
  fi

  if [ -z "$USER" ]
  then
    USER=rclone
    adduser \
      --disabled-password \
      --gecos "" \
      --no-create-home \
      --ingroup "$GROUP" \
      --uid "$UID" \
      "$USER" > /dev/null
  fi
fi

# Set time zone if passed in
if [ ! -z "$TZ" ]
then
  cp /usr/share/zoneinfo/$TZ /etc/localtime
  echo $TZ > /etc/timezone
fi

rm -f /tmp/sync.pid

# Check for source and destination ; launch config if missing
if [ -z "$SYNC_SRC" ] || [ -z "$SYNC_DEST" ]
then
  echo "INFO: No SYNC_SRC and SYNC_DEST found. Starting rclone config"
  su "$USER" -c "rclone config $RCLONE_OPTS"
  echo "INFO: Define SYNC_SRC and SYNC_DEST to start sync process."
else
  # SYNC_SRC and SYNC_DEST setup
  # run sync either once or in cron depending on CRON

  if [ -z "${SYNC_ON_STARTUP}" ]
  then
    echo "INFO: Add SYNC_ON_STARTUP=1 to perform a sync upon boot"
  else
    su "$USER" -c /sync.sh
  fi

  if [ -z "$CRONS" ]
  then
    echo "INFO: No CRON setting found. Stopping."
    echo "INFO: Add CRON=\"0 0 * * *\" to perform sync every midnight"
    exit 1
  else
    # Re-write cron shortcut
    case "$(echo "$CRON" | tr '[:lower:]' '[:upper:]')" in
        *@YEARLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 1 1 *" && CRONS="0 0 1 1 *";;
        *@ANNUALLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 1 1 *" && CRONS="0 0 1 1 *";;
        *@MONTHLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 1 * *" && CRONS="0 0 1 * * ";;
        *@WEEKLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 * * 0" && CRONS="0 0 * * 0";;
        *@DAILY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 * * *" && CRONS="0 0 * * *";;
        *@MIDNIGHT* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 * * *" && CRONS="0 0 * * *";;
        *@HOURLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 * * * *" && CRONS="0 * * * *";;
        *@* ) echo "WARNING: Cron shortcut $CRON is not supported. Stopping." && exit 1;;
        * ) CRONS=$CRON;;
    esac

    # Setup cron schedule
    crontab -d
    echo "$CRONS su $USER -c /sync.sh >>/tmp/sync.log 2>&1" > /tmp/crontab.tmp
    if [ -z "$CRON_ABORT" ]
    then
      echo "INFO: Add CRON_ABORT=\"0 6 * * *\" to cancel outstanding sync at 6am"
    else
      echo "$CRON_ABORT /sync-abort.sh >>/tmp/sync.log 2>&1" >> /tmp/crontab.tmp
    fi
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp

    # Start cron
    echo "INFO: Starting crond ..."
    touch /tmp/sync.log
    touch /tmp/crond.log
    crond -b -l 0 -L /tmp/crond.log
    echo "INFO: crond started"
    tail -F /tmp/crond.log /tmp/sync.log
  fi
fi
