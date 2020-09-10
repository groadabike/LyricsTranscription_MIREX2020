# Automatic Vocal Separation and Lyrics Transcription.

<div align="center">
<img src="images/system_pipeline.png" width="100%">

**Diagram of the system pipeline.** 

</div>

--------------------------------------------------------------------------------

This repository stores the system submitted to [MIREX 2020:Lyrics Transcription task](https://www.music-ir.org/mirex/wiki/2020:Lyrics_Transcription).

## What we submitted?

We submitted a system composed of two modules connected in a pipeline; a source separation and a lyrics transcription module. 
In this system, we utilised [Asteroid Pytorch-based audio source separation toolkit](https://github.com/mpariente/asteroid) 
for the construction of the vocal separation module. The lyrics transcription module was constructed using 
the [Kaldi ASR toolkit](http://kaldi-asr.org/). 

## Content
- [Installation](#installation)
- [Usage](#Usage)
- [Cite](#Cite)
- [References](#References)

## Installation
First, we need to download and install Kaldi toolkit.
The script extras/check_dependencies.sh will tell you if you need to install some Kaldi dependencies.  
Please, ensure you resolve all the comments before you can continue.
Be sure that the `--cuda-dir` parameter is directed to your cuda installation.
```bash
git clone https://github.com/kaldi-asr/kaldi.git kaldi --origin upstream

cd kaldi/tools
touch python/.use_default_python
./extras/check_dependencies.sh
make

cd ../scr
./configure --shared --cudatk-dir=/usr/local/cuda
make -j clean depend; make -j 4
```

Now, we will install some additional tool.
1. We will install miniconda; this will be saved in home/<user>
```bash
cd ../tools
./extras/install_miniconda.sh
```  
2. Please download SRILM from http://www.speech.sri.com/projects/srilm/download.html.  
Rename the file as:
```
e.g.:
mv srilm-1.7.3.tar.gz srilm.tar.gz
```
copy srilm.tar.gz into kaldi/tools and run 
```
./extras/install_srilm.sh
```

## Usage

```bash
run.sh 

```

## Cite
```
@inproceedings{Roa-Mirex2020,
  title={Automatic Vocal Enhancement and Lyrics Transcription},
  year={2020},
  booktitle={International Society for Music Information Retrieval (ISMIR)},
  author={Roa Dabike, Gerardo and Barker, Jon}
}
```

## References

