# MIDAS

Code for reduction of Near-Field and Far-Field High Energy Diffraction Microscopy (HEDM) data.

Neldermead is taken from http://people.sc.fsu.edu/~jburkardt/cpp_src/asa047/asa047.html and modified to include constraints and use as CUDA kernels.
SGInfo library used to calculate HKLs.
Need to install libtiff-dev and nlopt for compilation of NF-HEDM codes.


# Installation
To check help for installation, type "make help" in the terminal.
For individual help type "make helpnf" or "make helpff" in the terminal.
To compile individually, need to go to the sub-folder and "make" individually.
Would need NLOPT and TIFF packages.
For experimental CUDA codes: go to FF_HEDM folder and "make cuda". This doesn't require any external library.

# Stampede installation
[Stampede](https://portal.tacc.utexas.edu/user-guides/stampede) is a part of the [XSEDE](https://www.xsede.org/) 
supercomputing network. MIDAS far-field HEDM (FF) installation is tested on Stampede. To install MIDAS FF code on Stampede,
Log into Stampede and change to the Home directory.  
  `cd`  
  Clone MIDAS Github repo.  
  `git clone https://github.com/hmparanjape/MIDAS`  
  Change to the MIDAS FF folder  
  `cd MIDAS/FF_HEDM`  
  Load NetCDF library which is required by MIDAS  
  `module load netcdf`  
  Run the `make` command to compile binaries and create necessary scripts. This may take several minutes.  
  `make stampede`  
  In the end, you should see the following success message  
  `Congratulations, you can now use MIDAS on Stampede to run FarField analysis`

  In the `Example.Stampede` there is a sample parameter file and a job file to run MIDAS.
MIDAS jobs need to run on a `largmem` (large memory) node. Create a folder in the WORK directory
to run a simulation. Copy MIDAS FF sample files, modify them and submit a job.  
  `cdw`  
  `mkdir midas_test; cs midas_test`  
  `cp ~/MIDAS/FF_HEDM/Example.Stampede/* .`  
  `sbatch midas_test.job`  

# Local installation
To install on a local computer, go to FF_HEDM folder and "make local".
This will download NLOPT and SWIFT packages and install shortcuts in ${HOME}/.MIDAS directory.
