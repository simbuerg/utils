#!/bin/sh

# $1: Btrfs filesystem root
# $2: Root directory for snapshots
do_backup_in() {
  local fpref=$1
  local btrfsdir=$fpref/$2
  local prefix=$3
  local snapshot=
  local date_opt=

  case $prefix in
    "recent")  date_opt='+%M';;
    "hourly")  date_opt='+%H';;
    "daily")   date_opt='+%d';;
    "weekly")  date_opt='+%W';;
    "monthly") date_opt='+%m';;
    *)         date_opt='+%M';;
  esac

  snapshot="$btrfsdir/$prefix/$(date $date_opt)"

  if [ -d $snapshot ]; then
    /sbin/btrfs subvolume delete $snapshot 1> /dev/null
  fi

  if [ ! -d $snapshot ]; then
    /sbin/btrfs subvolume snapshot -r $fpref "$snapshot" 1> /dev/null
  else
    logger -p cron.error "Could not delete old snapshot $snapshot!"
  fi
}

do_backup_in $1 ".btrfs" $2
