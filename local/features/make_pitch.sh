#!/bin/bash
# Based-on https://github.com/LvHang/pitch

# Begin configuration section.
cmd=run.pl                     # run.pl|queue.pl
pitch_config=conf/pitch.conf
nj=4
compress=true
write_utt2num_frames=false
# End configuration section.

echo
echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. utils/parse_options.sh || exit 1;

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
   echo "Extract suitable pitch features for ASR using compute-and-process-kaldi-pitch-feats"
   echo "Usage: $0 [options] <data-dir> [<log-dir> [<pitch-dir>] ]";
   echo "e.g.: $0 data/ data/log data/information"
   echo "Note: <log-dir> defaults to <data-dir>/log, and <output-dir> defaults to <data-dir>/data"
   echo "Options: "
   echo "  --pitch-config <pitch-config-file> # config passed to compute-and-process-kaldi-pitch-feats etc. "
   echo "                                     # default is conf/pitch.conf"
   echo "   "
   exit 1;
fi

data=$1
if [ $# -ge 2 ]; then
  logdir=$2
else
  logdir=$data/log
fi
if [ $# -ge 3 ]; then
  pitch_dir=$3
else
  pitch_dir=$data/data
fi

# make $pitch_dir an absolute pathname.
pitch_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $pitch_dir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $pitch_dir || exit 1;
mkdir -p $logdir || exit 1;

scp=$data/wav.scp
required="$scp"

if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi


for f in $required; do
  if [ ! -f $f ]; then
    echo "make_pitch.sh: no such file $f"
    exit 1;
  fi
done


utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

for n in $(seq $nj); do
  # the next command does nothing unless $mfccdir/storage/ exists, see
  # utils/create_data_link.pl for more info.
  utils/create_data_link.pl $pitch_dir/raw_pitch_$name.$n.ark
done


if $write_utt2num_frames; then
  write_num_frames_opt="--write-num-frames=ark,t:$logdir/utt2num_frames.JOB"
else
  write_num_frames_opt=
fi


if [ -f $data/segments ]; then
    echo "$0 [info]: segments file exists: using that."

   split_segments=""
   for n in $(seq $nj); do
     split_segments="$split_segments $logdir/segments.$n"
   done

   utils/split_scp.pl $data/segments $split_segments || exit 1;
   rm $logdir/.error 2>/dev/null

    $cmd JOB=1:$nj $logdir/raw_pitch_$name.JOB.log \
     extract-segments scp,p:$scp $logdir/segments.JOB ark:- \| \
     compute-and-process-kaldi-pitch-feats --verbose=2 --config=$pitch_config ark:- ark:- \| \
     copy-feats --compress=$compress $write_num_frames_opt ark:- \
     ark,scp:$pitch_dir/raw_pitch_$name.JOB.ark,$pitch_dir/raw_pitch_$name.JOB.scp \
     || exit 1;

else
   echo "$0: [info]: no segments file exists: assuming wav.scp indexed by utterance."
   split_scps=""
   for n in $(seq $nj); do
     split_scps="$split_scps $logdir/wav_${name}.$n.scp"
   done

   utils/split_scp.pl $scp $split_scps || exit 1;

   $cmd JOB=1:$nj $logdir/pitch.JOB.log \
    compute-and-process-kaldi-pitch-feats --verbose=2  --config=$pitch_config \
    scp,p:$logdir/wav_${name}.JOB.scp ark:- \| \
    copy-feats $write_num_frames_opt --compress=$compress ark:- \
    ark,scp:$pitch_dir/raw_pitch_$name.JOB.ark,$pitch_dir/raw_pitch_$name.JOB.scp
fi


if [ -f $logdir/.error.$name ]; then
  echo "Error producing pitch features for $name:"
  tail $logdir/raw_pitch_${name}.1.log
  exit 1;
fi


# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $pitch_dir/raw_pitch_$name.$n.scp || exit 1;
done > $data/feats.scp || exit 1

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

echo "Succeeded creating pitch features for $name"

#for n in $(seq $nj); do
#    copy-feats ark:$pitch_dir/raw_pitch_$name.$n.ark ark,t:$pitch_dir/raw_pitch_$name.$n.text
#done
