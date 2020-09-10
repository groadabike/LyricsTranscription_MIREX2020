#!/bin/bash

# Vocal separation and lyrics trancription. 
# In this recipe, we implemented a vocal separation infer stage previous the ASR training.
# 1- The vocal separation stage is based on the Asteroid implementation
# of Convolutiona TasNet. We used a subset of the DAMP-VSEP corpus to train it.
# The transcription stage is based on the librispeech recipe. For training the ASR
# We used the DSing dataset, a preprocessed version of the DAMP Sing!300x30x2 
# published on Interspeech 2019. 
#
# Copyright 2020  Gerardo Roa Dabike
#                 University of Sheffield
# Apache 2.0
nj=1
stage=0
python_path=$HOME/miniconda3/bin/python

. ./path.sh
. ./cmd.sh

echo "Using steps and utils from WSJ recipe"
[[ ! -L "steps" ]] && ln -s $KALDI_ROOT/egs/wsj/s5/steps
[[ ! -L "utils" ]] && ln -s $KALDI_ROOT/egs/wsj/s5/utils


. ./utils/parse_options.sh
if [ $# != 2 ]; then
    echo "Usage: $0 [options] %input_audio <output>"
    echo "e.g.: Denoting the input audio file path %input_audio, "
    echo "and the path to the output file as %output, the script should be called as"
    echo "$0 --python_path python %input_audio %output"
    echo "[Option]"
    echo "--python_path     Path to the python you'll use for the transcription"
    echo ""   
    exit 1;
fi

input_audio=$1
output=$2

audio_file=${input_audio##*/}
audio_id=${audio_file%*".wav"}
audio_id=${audio_id//./_}

# Exit on error
set -e 
set -o pipefail

# This script needs sox and ffmpeg
./local/check_tools.sh || exit 1

dir=exp/chain/tdnn_sp
graph_dir=$dir/graph_3G
if [[ ! -f $graph_dir/HCLG.fst ]]; then
  pushd $graph_dir
  tar -xf HCLG.tar.xz HCLG.fst
  popd
fi
lang=data/lang_4G
if [[ ! -f $lang/G.fst ]]; then
  pushd $lang
  tar -xf G.tar.xz G.fst
  popd
fi

BLUE='\033[1;34m'
GREEN='\033[1;32m'
NC='\033[0m' # No colour
if [[ stage -le 0 ]]; then
  echo -e "Starting transcription of ${GREEN}${input_audio}${NC}"
  echo -ne "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Enhancing vocal audio segment\r"

  $python_path local/audio_enhancement.py \
      --out_dir data/$audio_id \
      --input_audio $input_audio
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Enhancing vocal audio segment........done"
fi

mfcc_dir=data/$audio_id/${audio_id}_mfcc
mkdir -p $mfcc_dir
if [[ stage -le 1 ]]; then
  echo -ne "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Preparing data for transcription\r"
  $python_path local/prepare_data.py \
      --audio_id $audio_id \
      --audio data/$audio_id/"enhanced.wav" \
      --datadir $mfcc_dir
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Preparing data for transcription.......done"
fi

if [[ stage -le 2 ]]; then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting high resolution MFCC"

    utils/fix_data_dir.sh $mfcc_dir
    steps/make_mfcc.sh --nj $nj --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" $mfcc_dir
    steps/compute_cmvn_stats.sh $mfcc_dir

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting high resolution MFCC......done"
fi

ivector_dir=data/$audio_id/${audio_id}_ivectors
if [[ stage -le 3 ]]; then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting i-vectors"
    steps/online/nnet2/extract_ivectors_online.sh \
      --cmd "$train_cmd" --nj "$nj" \
      $mfcc_dir \
      exp/nnet3/extractor \
      $ivector_dir

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting i-vectors......done"
fi

feat_to_join=$mfcc_dir
pitch_conf=conf/pitch.conf
perturbation_conf=conf/perturbation_feat.ini
dir=exp/chain/tdnn_sp

pitch_dir=data/$audio_id/${audio_id}_pitch
feat_to_join="$feat_to_join  $pitch_dir"
if [[ stage -le 4 ]]; then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting pitch features"

  if [ -f "$pitch_dir/feats.scp" ]; then
    echo $pitch_dir/feats.scp " exist! It will not be extracted again"
  else
    utils/copy_data_dir.sh $mfcc_dir $pitch_dir
    utils/fix_data_dir.sh $pitch_dir
    local/features/make_pitch.sh --nj $nj --cmd "$train_cmd" \
      --pitch-config $pitch_conf $pitch_dir
    steps/compute_cmvn_stats.sh $pitch_dir
  fi

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting pitch features......done"
fi

perturb_dir=data/$audio_id/${audio_id}_perturbation
feat_to_join="$feat_to_join  $perturb_dir"
if [[ stage -le 5 ]]; then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting perturbation features"

  if [ -f "$perturb_dir/feats.scp" ]; then
    echo $perturb_dir/feats.scp " exist! It will not be extracted again"
  else
    utils/copy_data_dir.sh $mfcc_dir $perturb_dir
    utils/fix_data_dir.sh $perturb_dir
    local/features/make_jitter.sh --nj $nj --cmd "$train_cmd" \
      --jitter_conf $perturbation_conf --python_path $python_path \
      $perturb_dir
    steps/compute_cmvn_stats.sh $perturb_dir
  fi

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Extracting perturbation features......done"
fi

paste_dir=data/$audio_id/${audio_id}_pasted
if [[ stage -le 6 ]]; then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Joining features"

  steps/paste_feats.sh --length_tolerance 10 --nj $nj \
    --cmd "$train_cmd" $feat_to_join \
    ${paste_dir} ${paste_dir}/log ${paste_dir}/data
  steps/compute_cmvn_stats.sh ${paste_dir} \
      ${paste_dir}/log ${paste_dir}/data

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Joining features......done"
fi


lmwt=11
wip=0.0
graph_dir=$dir/graph_3G
if [[ $stage -le 7 ]]; then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Decoding audio file"

  rm $dir/.error 2>/dev/null || true
  (
  steps/nnet3/decode.sh \
    --acwt 1.0  \
    --post-decode-acwt 10.0 \
    --nj $nj \
    --num-threads 4 \
    --cmd "$decode_cmd" \
    --skip_scoring true \
    --online-ivector-dir \
    $ivector_dir \
    $graph_dir \
    $paste_dir \
    $dir/decode_${audio_id}_3G || exit 1

    steps/lmrescore.sh --cmd "$decode_cmd" \
      --self-loop-scale 1.0 --skip_scoring true \
      data/lang_{3G,4G} \
      $paste_dir \
      $dir/decode_${audio_id}_{3G,4G} || exit 1
  ) || touch $dir/.error &
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in decoding"
    exit 1
  fi

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Decoding audio file......done"
fi

decode_dir=$dir/decode_${audio_id}_4G
if [[ $stage -le 8 ]];then
  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Finalising process"

  lattice-1best --lm-scale=$lmwt --acoustic-scale=0.1 --word-ins-penalty=$wip \
    "ark,s,cs:gunzip -c $decode_dir/lat.1.gz |" ark:- |
  nbest-to-linear ark,t:- ark,t:data/${audio_id}/ali \
    "ark,t:|int2sym.pl -f 2- data/lang_4G/words.txt > data/${audio_id}/transcription" \
    ark,t:data/${audio_id}/lm_cost \
    ark,t:data/${audio_id}/ac_cost

  echo -e "${BLUE}[${GREEN}$audio_id${BLUE}]${NC} Finalising process......done"
fi

if [[ $stage -le 9 ]]; then
  mkdir -p "$(dirname "$output")"
  cut -f 2- -d ' ' data/${audio_id}/transcription > $output
fi

echo "Transcription save on $output"
