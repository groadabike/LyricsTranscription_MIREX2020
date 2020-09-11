#!/bin/bash

# Copyright 2019 Gerardo Roa
#                University of Sheffield
# Apache 2.0
# jitter tracking using dynamic programing
# To be run from .. (one directory up from here)
# see ../run.sh for example

# Begin configuration section.
nj=4
cmd=run.pl
compress=true
jitter_conf=
write_utt2num_frames=false  # if true writes utt2num_frames
python_path=
# End configuration section.

echo
#echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# -lt 1 ] || [ $# -gt 3 ]; then
   echo "Usage: $0 [options] <data-dir> [<log-dir> [<mfcc-dir>] ]";
   echo "e.g.: $0 data/train exp/make_jitter/train jitter"
   echo "Note: <log-dir> defaults to <data-dir>/log, and <mfccdir> defaults to <data-dir>/data"
   echo "Options: "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --write-utt2num-frames <true|false>     # If true, write utt2num_frames file."
   exit 1;
fi


data=$1
if [ $# -ge 2 ]; then
  logdir=$2
else
  logdir=$data/log
fi
if [ $# -ge 3 ]; then
  jitter_dir=$3
else
  jitter_dir=$data/data
fi

# make $jitter_dir an absolute pathname.
jitter_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $jitter_dir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $jitter_dir || exit 1;
mkdir -p $logdir || exit 1;
mkdir -p $jitter_dir/tmp || exit 1;

scp=$data/wav.scp

required="$scp"

if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_jitter.sh: no such file $f"
    exit 1;
  fi
done

utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

for n in $(seq $nj); do
  # the next command does nothing unless $mfccdir/storage/ exists, see
  # utils/create_data_link.pl for more info.
  utils/create_data_link.pl $jitter_dir/raw_jitter_$name.$n.ark
done


if [ -f $data/segments ]; then
  echo "$0 [info]: segments file exists: using that."

  split_segments=""
  for n in $(seq $nj); do
    split_segments="$split_segments $logdir/segments.$n"
  done

  utils/split_scp.pl $data/segments $split_segments || exit 1;
  rm $logdir/.error 2>/dev/null

    $cmd JOB=1:$nj $logdir/make_jitter_${name}.JOB.log \
      $python_path local/features/make_jitter.py --jitter_conf $jitter_conf --segfile $logdir/segments.JOB \
      $data $logdir/make_jitter_${name}.JOB.log $jitter_dir

else
    echo "$0 [info]: no segments file exists: assuming wav.scp indexed by utterance."
    $cmd JOB=1:$nj $logdir/make_jitter_${name}.JOB.log \
      $python_path local/features/make_jitter.py --jitter_conf $jitter_conf \
      --segfile $data/wav.scp \
      $data $logdir/make_jitter_${name}.JOB.log $jitter_dir
fi

# create ark and scp files
for n in $(seq $nj); do

    if $write_utt2num_frames; then
      write_num_frames_opt="--write-num-frames=ark,t:$logdir/utt2num_frames.$n"
    else
      write_num_frames_opt=
    fi

    copy-feats --compress=$compress $write_num_frames_opt ark,t:$jitter_dir/raw_jitter_$name.$n.txt \
      ark,scp:$jitter_dir/raw_jitter_$name.$n.ark,$jitter_dir/raw_jitter_$name.$n.scp
done


# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $jitter_dir/raw_jitter_$name.$n.scp #|| exit 1;
done > $data/feats.scp #|| exit 1

if $write_utt2num_frames; then
  for n in $(seq $nj); do
    cat $logdir/utt2num_frames.$n || exit 1;
  done > $data/utt2num_frames || exit 1
  rm $logdir/utt2num_frames.*
fi


rm $logdir/wav_${name}.*.scp  $logdir/segments.* 2>/dev/null

nf=`cat $data/feats.scp | wc -l`
nu=`cat $data/utt2spk | wc -l`
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

if [ $nf -lt $[$nu - ($nu/20)] ]; then
  echo "Less than 95% the features were successfully generated.  Probably a serious error."
  exit 1;
fi

echo "Succeeded creating jitter tracking using dynamic programing features for $name"