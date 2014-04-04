#!/bin/bash
# Where is the base disk?
BASE_DEV=/dev/sdb
BASE_DEV_UUID=/dev/disk/by-uuid/815c19c8-b565-42dc-893d-758ba7a6d96f
BASE_DIR=/backup

# $1: reference snapshot
# $2: date unit (days/weeks/years/hours..)
# $3: base dir to look in
# $4: dateopt (options for date command, should match $2)
PREV_SNAPSHOT=
get_previous() {
  local target_dir=$(dirname $1)
  local target=$(basename $1)
  local unit=$2
  local basedir=$3
  local dateopt=$4
  local i=$(( $(date $dateopt) - $(( 10#$target - 1)) ))
  local prev=$(date --date="$i $unit ago" "$dateopt")
  local prevdir=$basedir/$target_dir/$prev

#  echo "get_previous prev $prev"
#  echo "get_previous target $target"

  while [[ ! $prev = $target ]] && [[ ! -d $prevdir ]];
  do
	prev=$(date --date="$i $unit ago" "$dateopt")		
  	prevdir=$basedir/$target_dir/$prev
	i=$((i + 1))
  done

  PREV_SNAPSHOT=$prevdir
  return $prev
}

# $1: device
# $2: mountpoint
dev_is_mounted_at() {
  local base_dev=$1
  local base_dir=$2

  read is_mounted_at < <(df $BASE_DEV_UUID | tail -1 | awk '{print $$1==$base_dev && $$6==$base_dir}')
  return $is_mounted_at
}

PATH_SEGMENTS=()
split_path() {
	local IFS=/
	set -f
	PATH_SEGMENTS=( $@ )
	set +f
}

send_to_dock() {
	src_fs=$1
	tgt_fs=$2
	snapshot_type=$3
	case $snapshot_type in
		"recent")  date_opt='+%M' ; unit="minutes";;
		"hourly")  date_opt='+%H' ; unit="hours";;
		"daily")   date_opt='+%d' ; unit="days";;
		"weekly")  date_opt='+%W' ; unit="weeks";;
		"monthly") date_opt='+%m' ; unit="months";;
		*)         date_opt='+%H' ; unit="hours";;
	esac
	
	if dev_is_mounted_at $BASE_DEV $BASE_DIR; then
		echo "Mounting $BASE_DEV at $BASE_DIR"
		# /etc/fstab muss einen Eintrag hierfür haben
		/bin/mount $BASE_DEV_UUID $BASE_DIR
	fi

	prev_snapshot_date=""
	prev_snapshot=""
	prev_tgt_name=""
	
	# Get all snapshots for subvolume at $src_fs (ordered by creation time)
	for snapshot in $(btrfs sub show $src_fs | awk '{print $NF}' | grep $snapshot_type)
	do
		snapshot_date="$(btrfs sub show $src_fs/$snapshot | grep Creation | awk '{ print $3}')"
		tgt_base_name=$(basename $src_fs)
		if [ $tgt_base_name = "/" ]; then
			tgt_base_name="root"
		fi
		tgt_name=$tgt_base_name-$snapshot_type-$snapshot_date

		# Send the snapshot (incremental, if possible)
		send_opts=
		if [ -d $tgt_fs/$prev_tgt_name -a "$prev_tgt_name" != "" ]; then
			send_opts="-p $prev_snapshot"
		fi
		
		if [ ! -d $tgt_fs/$tgt_name ]; then
			echo "btrfs send $send_opts $src_fs/$snapshot | btrfs receive $tgt_fs"
			btrfs send $send_opts $src_fs/$snapshot | btrfs receive $tgt_fs
			echo "btrfs sub snap -r $tgt_fs/$(basename $snapshot) $tgt_fs/$tgt_name"
			btrfs sub snap -r $tgt_fs/$(basename $snapshot) $tgt_fs/$tgt_name
			echo "btrfs sub del $tgt_fs/$(basename $snapshot)"
			btrfs sub del $tgt_fs/$(basename $snapshot)
		fi

		# The last sent snapshot is older than the next (btrfs sub show gives them ordered)
		prev_tgt_name=$tgt_name
		prev_snapshot=$src_fs/$snapshot
		prev_snapshot_date=$snapshot_date
	done
}

if [ -b $BASE_DEV_UUID ]; then
  send_to_dock $1 $2 $3
fi