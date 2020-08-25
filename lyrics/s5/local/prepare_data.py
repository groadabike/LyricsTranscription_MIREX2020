import argparse
import os
import soundfile as sf

class Song:
    def __init__(self, audio_id, audio, datadir, gender):
        self.audio_id = audio_id
        self.audio = audio
        self.datadir = datadir
        self.gender = gender
        self.rec_id = f"{self.audio_id}_rec-{gender.upper()}"
        self.utt_id = f"{self.audio_id}_01-{gender.upper()}"
        self.spk_id = f"{self.audio_id}_spk-{gender.upper()}"

    def spk2gender(self):
        s2g_line = f"{self.spk_id} {self.gender}"
        with open(os.path.join(self.datadir, 'spk2gender'), 'w') as s2g:
            s2g.write(f"{s2g_line}")

    def wavscp(self):
        wavscp_line = f"{self.rec_id} sox {self.audio} "
        wavscp_line += "-G -t wav -r 16000 -c 1 - remix 1 |"
        with open(os.path.join(self.datadir, 'wav.scp'), 'w') as wavscp:
            wavscp.write(f"{wavscp_line}")

    def segments(self):
        duration = sf.info(self.audio).duration
        segments_line = f"{self.utt_id} {self.rec_id} {0.0} {duration}"
        with open(os.path.join(self.datadir, 'segments'), 'w') as segments:
            segments.write(f"{segments_line}")

    def utt2spk(self):
        utt2spk_line = f"{self.utt_id} {self.spk_id}"
        with open(os.path.join(self.datadir, 'utt2spk'), 'w') as utt2spk:
            utt2spk.write(f"{utt2spk_line}")


def main(args):
    song = Song(args.audio_id, args.audio, args.datadir, 'f')
    song.spk2gender()
    song.wavscp()
    song.segments()
    song.utt2spk()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio_id", type=str,
                        help="Audio identifier.")
    parser.add_argument("--audio", type=str, required=True,
                        help="Path to enhanced audio.")
    parser.add_argument("--datadir", type=str, required=True,
                        help="Path to Kaldi data")
    args = parser.parse_args()
    main(args)