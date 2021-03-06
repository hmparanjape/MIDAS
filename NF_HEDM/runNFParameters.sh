#!/bin/bash -eu
cmdname=$(basename $0)
if [[ ${#*} != 5 ]];
then
  echo "Usage: ${cmdname} parameterfile nCPUS processImages FFSeedOrientations MultiGridPoints"
  echo "Eg. ${cmdname} ParametersFile.txt 320 0 0 0"
  echo "FFSeedOrientations is when either Orientations exist already (0) or when you provide a FF Orientation file (1)."
  echo "MultiGridPoints is 0 when you just want to process one spot, otherwise if it is 1, then provide the multiple points"
  echo "in the parameter file."
  echo "processImages = 1 if you want to reduce raw files, 0 otherwise"
  exit 1
fi

if [[ $1 == /* ]]; then TOP_PARAM_FILE=$1; else TOP_PARAM_FILE=$(pwd)/$1; fi
NCPUS=$2
processImages=$3
FFSeedOrientations=$4
MultiGridPoints=$5

BINfolder=/clhome/TOMO1/PeaksAnalysisHemant/HEDM_V2/NF_HEDM/

# Go to the right folder
DataDirectory=$( awk '$1 ~ /^DataDirectory/ { print $2 }' ${TOP_PARAM_FILE} )
cd ${DataDirectory}

# Make hkls.csv
${BINfolder}/bin/GetHKLList ${TOP_PARAM_FILE}

echo "Making hexgrid."
${BINfolder}/bin/MakeHexGrid $TOP_PARAM_FILE
if [[ ${MultiGridPoints} == 0 ]];
then
  echo "Now choose the grid point to process, press enter to continue"
  echo "The grid points numbers are first column, position (x,y) is 4 and 5 column"
  read dummyVar
  cat -n grid.txt
  echo "REMEMBER: Subtract 1 from the line number (first column)."
  read GRIDPOINTNR
  echo "You entered: ${GRIDPOINTNR}"
fi

echo "Making diffraction spots."

GrainsFile=$( awk '$1 ~ /^GrainsFile/ { print $2 }' ${TOP_PARAM_FILE} )
SeedOrientations=$( awk '$1 ~ /^SeedOrientations/ { print $2 }' ${TOP_PARAM_FILE} )

if [[ ${FFSeedOrientations} == 1 ]];
then
    ${BINfolder}/bin/GenSeedOrientationsFF2NFHEDM $GrainsFile $SeedOrientations
fi

NrOrientations=$( wc -l ${SeedOrientations} | awk '{print $1}' )

echo "NrOrientations ${NrOrientations}" >> ${TOP_PARAM_FILE}
${BINfolder}/bin/MakeDiffrSpots $TOP_PARAM_FILE

if [[ ${processImages} == 1 ]];
then
  echo "Reducing images."
  PATH=/clhome/TOMO1/PeaksAnalysisHemant/HEDM_V2/SWIFT/swift-0.95-RC7/bin:$PATH
  NDISTANCES=$( awk '$1 ~ /^nDistances/ { print $2 }' ${TOP_PARAM_FILE} )
  NRFILESPERDISTANCE=$( awk '$1 ~ /^NrFilesPerDistance/ { print $2 }' ${TOP_PARAM_FILE} )
  NRPIXELS=$( awk '$1 ~ /^NrPixels/ { print $2 }' ${TOP_PARAM_FILE} )
  echo "Median"
  swift -sites.file ${BINfolder}sites${NCPUS}.xml -tc.file ${BINfolder}tc -config ${BINfolder}cf ${BINfolder}ProcessMedianParallel.swift \
    -paramfile=${TOP_PARAM_FILE} -NrLayers=${NDISTANCES} -NrFilesPerLayer=${NRFILESPERDISTANCE} -NrPixels=${NRPIXELS}
  echo "Image"
  swift -sites.file ${BINfolder}sites${NCPUS}.xml -tc.file ${BINfolder}tc -config ${BINfolder}cf ${BINfolder}ProcessImagesParallel.swift \
    -paramfile=${TOP_PARAM_FILE} -NrLayers=${NDISTANCES} -NrFilesPerLayer=${NRFILESPERDISTANCE} -NrPixels=${NRPIXELS}
fi

echo "Finding parameters."
if [[ ${MultiGridPoints} == 0 ]];
then
  ${BINfolder}/bin/FitOrientationParameters $TOP_PARAM_FILE ${GRIDPOINTNR}
else
  ${BINfolder}/bin/FitOrientationParametersMultiPoint $TOP_PARAM_FILE
fi
