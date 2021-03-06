
import os
import torch
import argparse
import numpy as np
import soundfile as sf
import librosa

from asteroid.models import ConvTasNet
from asteroid.dsp.overlap_add import LambdaOverlapAdd

import warnings
warnings.simplefilter(action='ignore')


parser = argparse.ArgumentParser()
parser.add_argument('--input_audio', type=str, required=True)
parser.add_argument('--out_dir', type=str, required=True,
                    help='Directory where the enhanced tracks will be stored.')
parser.add_argument('--use_gpu', type=int, default=0,
                    help='Whether to use the GPU for model execution')
parser.add_argument('--sample_rate', type=int, default=16000)
parser.add_argument('--enh_samples', type=int, default=18000)


def load_audio(audio_path, sr):
    x, _ = librosa.load(
                audio_path,
                sr=sr,
                mono=True,
                dtype='float32'
                )
    return x
 
 
def main(conf):
    #model = ConvTasNet.from_pretrained('groadabike/ConvTasNet_DAMP-VSEP_enhboth')
    model = ConvTasNet.from_pretrained('local/vsep/model.pth')

    model = LambdaOverlapAdd(
        nnet=model,  # function to apply to each segment.
        n_src=2,  # number of sources in the output of nnet
        window_size=conf['enh_samples'],  # Size of segmenting window
        hop_size=None,  # segmentation hop size
        window="hanning",  # Type of the window (see scipy.signal.get_window
        reorder_chunks=False,  # Whether to reorder each consecutive segment.
        enable_grad=False,  # Set gradient calculation on of off (see torch.set_grad_enabled)
    )

    # Handle device placement
    if conf['use_gpu']:
        model.cuda()

    model_device = next(model.parameters()).device

    os.makedirs(conf['out_dir'], exist_ok=True)

    # Loading mixture
    mix = load_audio(conf["input_audio"], conf["sample_rate"])
    mix = torch.from_numpy(mix)
    mix = mix.to(model_device)

    # Enhance mixture
    est_sources = model.forward(mix.unsqueeze(0).unsqueeze(1))
    mix_np = mix.squeeze(0).cpu().data.numpy()
    
    est_sources_np = est_sources.squeeze(0).cpu().data.numpy()
    est_src = est_sources_np[0]
   
    # Save enhanced
    est_src *= np.max(np.abs(mix_np)) / np.max(np.abs(est_src))
    sf.write(os.path.join(conf['out_dir'], 'enhanced.wav'),
             est_src, conf['sample_rate'])


if __name__ == '__main__':
    args = parser.parse_args()
    arg_dic = dict(vars(args))
    main(arg_dic)
