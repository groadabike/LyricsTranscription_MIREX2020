#!/usr/bin/env python

# Copyright (C) 2019 Gerardo Roa


from __future__ import print_function
from __future__ import division

import os
import numpy as np
import subprocess
import parselmouth
from parselmouth.praat import call
import librosa
import time
import argparse
from argparse import RawTextHelpFormatter
import configparser

import warnings
import logging

np.set_printoptions(suppress=True)
logging.captureWarnings(True)
warnings.simplefilter(action='ignore', category=FutureWarning)

__author__ = 'Gerardo Roa - University of Sheffield'


def create_folder(fd):
    if not os.path.exists(fd):
        os.makedirs(fd)


def extract_jitter(data_dir, record, wav, sr, logging, add_jitta, add_ddp, add_shimmer, add_hnr):
    """
    Extract the jitter from the audio using
    :param data_dir:
    :param record:
    :param wav:
    :param sr:
    :return:
    """

    if os.path.exists(os.path.join(data_dir, 'segments')):
        # running sox command when segment exist
        # subprocess.call in python 2.7
        # subprocess.run in python 3.5 or above
        process = subprocess.Popen(record.split(',', 1)[-1], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = process.communicate()
        # if out:
        #     logging.warning(out)
        # if err:
        #     logging.error(err)

    # extract features
    # segment exist
    if os.path.exists(os.path.join(data_dir, 'segments')):
        sound = parselmouth.Sound(wav).convert_to_mono()
    # file from wav.scp
    else:
        sound = parselmouth.Sound(record.split(',')[1]).convert_to_mono()
    sound.override_sampling_frequency(16000.0)

    y, sr = librosa.load(wav, sr=sr, mono=True)
    len_frames = librosa.util.frame(y, frame_length=int(0.025 * sr), hop_length=int(0.010 * sr)).shape[1]

    f0min, f0max = 75, 1000
    pointProcess = call(sound, "To PointProcess (periodic, cc)", f0min, f0max)

    time_initial, time_final = 0, 0
    period_floor = 0.0001
    period_ceiling = 0.02
    maximum_period_value = 1.3

    feat_vector = []
    if add_jitta:
        feat_vector.append(call(pointProcess, "Get jitter (local, absolute)", time_initial, time_final,
                                period_floor, period_ceiling, maximum_period_value))
    if add_ddp:
        feat_vector.append(call(pointProcess, "Get jitter (ddp)", time_initial, time_final,
                                      period_floor, period_ceiling, maximum_period_value))

    if add_shimmer:
        feat_vector.append( call([sound, pointProcess], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6))

    if add_hnr:
        harmonicity = call(sound, "To Harmonicity (cc)", 0.01, 75, 0.1, 1.0)
        feat_vector.append(call(harmonicity, "Get mean", 0, 0))

    len_frames = librosa.util.frame(y, frame_length=int(0.025 * sr), hop_length=int(0.010 * sr)).shape[1]
    feature = np.tile(np.stack(feat_vector, axis=-1), (len_frames, 1))

    return feature


def write_feat2file(feat_file, feature):
    for feat in feature:
        print(feat)
        if '-F' in feat or '-M' in feat:
            feat_file.write("{}  [\n".format(feat))
        else:
            feat = list(np.nan_to_num(feat))
            for pos, f in enumerate(feat):
                if pos + 1 == len(feat):
                    feat_file.write("  " + np.array2string(f, formatter={'float_kind':lambda f: "%.6f" % f}).replace('[','').replace(']','') + " ]\n")
                else:
                    feat_file.write("  " + np.array2string(f, formatter={'float_kind':lambda f: "%.6f" % f}).replace('[','').replace(']','') + " \n")


def jitter_tracking(data_dir, feat_dir, log_file, seg_file, mode, sr, nj, add_jitta, add_ddp, add_shimmer, add_hnr):
    """
    This function assumed that the directories data_dir and bt_dir, and the directory for the file log_file exists.

    :param data_dir: Path to the data set. e.g data/train
    :param feat_dir: Path where the features will be save. e.g. jitter_feats
    :param log_file: Path to the log file. e.g. jitter_feats/log/jitter_feats.1.txt
    :param seg_file: Path to the segment file when mode=segment. e.g. jitter_feats/temp/segment.1
    :param mode:     Mode in which the data is split. options = [segment when segment file is used, or wavscp when no segment is used]
    :param sr:       Sample Rate
    :param nj:       Number of jobs
    :return:
    """

    # Set tmp.wav
    tmp_dir = os.path.join(feat_dir, "tmp")
    create_folder(tmp_dir)

    tmp_wav = os.path.join(tmp_dir, "tmp.{}.wav".format(nj))

    logging.basicConfig(filename=log_file, level=logging.INFO, filemode='w',
                        format="%(asctime)s [%(pathname)s:%(lineno)s - %(funcName)s - %(levelname)s ] %(message)s")

    logging.basicConfig(filename=log_file, level=logging.WARNING, filemode='w',
                        format="%(asctime)s [%(pathname)s:%(lineno)s - %(funcName)s - %(levelname)s ] %(message)s")

    logging.basicConfig(filename=log_file, level=logging.ERROR, filemode='w',
                        format="%(asctime)s [%(pathname)s:%(lineno)s - %(funcName)s - %(levelname)s ] %(message)s")

    feat_file = open(os.path.join(feat_dir, 'raw_jitter_{}.{}.txt'.format(data_dir.split('/')[-1], nj)), "w")

    # head of log file
    current_time = "{}-{}-{} {}:{}:{}".format(
        time.localtime().tm_year, time.localtime().tm_mon, time.localtime().tm_mday,
        time.localtime().tm_hour, time.localtime().tm_min, time.localtime().tm_sec)
    logging.info('# {}'.format(current_time))
    logging.info('# Starting beat-tracking extraction')
    logging.info('# Using dynamic programing')
    logging.info('# ')

    # when segment file exist
    if mode == 'segment':
        wavscp = [f.rstrip() for f in open(os.path.join(data_dir, "wav.scp"))]
        segments = [f.rstrip() for f in open(seg_file)]
        recordings = []
        for segment in segments:
            utt_id, rec_id, start, end = segment.split(" ")
            _, ext_filename = [f for f in wavscp if rec_id in f][0].split(" ", 1)
            recordings.append('{}, {} sox -t wav - -t wav {} trim {} {}'.format(
                    utt_id, ext_filename, tmp_wav, start, float(end)-float(start)))

    # No segment file exist, use wav.scp
    else:
        # TODO implement when no segment file is provided
        recordings = [f.rstrip() for f in open(os.path.join(data_dir, "wav.scp"))]
        print(recordings)

    for counter, record in enumerate(recordings):

        # segment ID
        features_list = []
        features_list.append(record.split(',')[0])  # add in list for feat file
        logging.info("Processed features for key {}".format(record.split(',')[0]))

        if (counter + 1) % 10 == 0:
            logging.info("Processed {} utterances".format(counter +1))

        # Extract the beats from current recording
        feature_vector = extract_jitter(data_dir, record, tmp_wav, sr, logging, add_jitta, add_ddp, add_shimmer, add_hnr)

        # add features to the list
        features_list.append(feature_vector)
        write_feat2file(feat_file, features_list)
        os.remove(tmp_wav)
    return


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Usage: %(prog)s <data-dir> [<log-dir> [<feat-dir>]]\n'
                    'e.g.: %(prog)s data/train exp/make_jitter/train jitter_feat\n'
                    'Note: <log-dir> defaults to <data-dir>/log, and  <feat-dir> defaults to <data-dir>/jitter\n'
                    'Options:\n'
                    '--mode               # Specify if use segment or wav.scp files'
                    '                     # values are [segment, wavscp]'
                    '--segfile            # path to segment file'
                    '                     # this is a mandatory file when --mode=segment'
                    '--sr                 # Sample rate, default=16000',
        formatter_class=RawTextHelpFormatter
    )
    parser.add_argument("datadir", type=str, help="Path to the <data-dir>")

    parser.add_argument("logfile", type=str, help="Path to <log-file>",
                        nargs='?', default="")

    parser.add_argument("featdir", type=str, help="Path to <feat-dir>",
                        nargs='?', default="")

    parser.add_argument("--jitter_conf", type=str, help="Path to config file",
                        nargs='?', default="")

    parser.add_argument("--mode", type=str, help="Path to the Workspace directory",
                        choices=['segment', 'wavscp'], default='segment')

    parser.add_argument("--segfile", type=str, help="Path to <segment-file>",
                        default="")

    parser.add_argument("--sr", type=int, help="Sample rate ", default=16000)

    parser.add_argument('--version', action='version',
                        version='%(prog)s 0.1')

    args = parser.parse_args()
    config = configparser.ConfigParser()
    if len(args.jitter_conf):
        config.read(args.jitter_conf)

    mode = config['data'].get('mode') if 'mode' in config['data'] else args.mode
    if mode == 'segment' and args.segfile == "":
        parser.error("--mode=segment requires --segfile=<segment-file>.")

    sr = config['data'].getint('sample_rate') if 'sample_rate' in config['data'] else args.sr

    datadir = args.datadir
    logfile = os.path.join(datadir, "log", "make_jitter.01.log") if args.logfile == "" else args.logfile
    featdir = os.path.join(datadir, "jitter") if args.featdir == "" else args.featdir

    segfile = args.segfile

    nj = logfile.split(".")[-2]

    add_jitta = config['default'].getboolean('add_jitta') if 'add_jitta' in config['default'] else True
    add_ddp = config['default'].getboolean('add_ddp') if 'add_ddp' in config['default'] else True
    add_shimmer = config['default'].getboolean('add_shimmer') if 'add_shimmer' in config['default'] else True
    add_hnr = config['default'].getboolean('add_hnr') if 'add_hnr' in config['default'] else True



    create_folder(os.path.dirname(logfile))
    create_folder(featdir)

    jitter_tracking(datadir, featdir, logfile, segfile, mode, sr, nj, add_jitta, add_ddp, add_shimmer, add_hnr)


if __name__ != '__main__':
    raise ImportError('This script can only be run, and can\'t be imported')


