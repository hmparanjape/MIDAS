#!/bin/bash -eu

if [[ ${#*} != 6 ]];
then
  echo "Usage: $0 top_parameter_file(full_path) nCPUS FFSeedOrientations ProcessImages startLayerNr endLayerNr"
  echo "Eg. $0 ParametersFile.txt 384 1(or 0) 1(or 0) 1 5"
  echo "This will run from layer 1 to 5."
  echo "This will produce the output in the run folder."
  echo "FFSeedOrientations is when either Orientations exist already (0) or when you provide a FF Orientation file (1)."
  echo "ProcessImages is whether you want to process the diffraction images (1) or if they were processed earlier (0)."
  echo "NOTE: run from the folder with the Key.txt, DiffractionSpots.txt, OrientMat.txt and ParametersFile.txt"
  echo "At least the parameters file should be in the folder from where the command is executed."
  exit 1
fi

PARAMFILE=$1
NCPUS=$2
FFSEEDORIENTATIONS=$3
PROCESSIMAGES=$4
STARTLAYERNR=$5
ENDLAYERNR=$6
STEM=$( awk '$1 ~ /^OrigFileName/ { print $2 }' ${PARAMFILE} )
CHART=/
FOLDER=${STEM%$CHART*}
FILENAME=${STEM#*$CHART}
OVERALLSTARTNR=$( awk '$1 ~ /^OverallStartNr/ { print $2 }' ${PARAMFILE} )
STARTGLOBALPOS=$( awk '$1 ~ /^GlobalPositionFirstLayer/ { print $2 }' ${PARAMFILE} )
LAYERTHICKNESS=$( awk '$1 ~ /^LayerThickness/ { print $2 }' ${PARAMFILE} )
PFSTEM=${PARAMFILE%.*}
WFIMAGES=$( awk '$1 ~ /^WFImages/ { print $2 }' ${PARAMFILE} )
NDISTANCES=$( awk '$1 ~ /^nDistances/ { print $2 }' ${PARAMFILE} )
NRFILESPERDISTANCE=$( awk '$1 ~ /^NrFilesPerDistance/ { print $2 }' ${PARAMFILE} )
DATADIRECTORY=$( awk '$1 ~ /^DataDirectory/ { print $2 }' ${PARAMFILE} )

for ((LAYERNR=${STARTLAYERNR}; LAYERNR<=${ENDLAYERNR}; LAYERNR++))
do
    THISPARAMFILE=${PFSTEM}Layer${LAYERNR}.txt
    cp ${PARAMFILE} ${THISPARAMFILE}
    if [[ $WFIMAGES -eq 1 ]]; then
        INCREASEDFILES=$(($NRFILESPERDISTANCE+10))
    else
        INCREASEDFILES=$NRFILESPERDISTANCE
    fi
    STARTFILENRTHISLAYER=$(($(($(($LAYERNR-1))*$(($NDISTANCES))*$(($INCREASEDFILES))))+$OVERALLSTARTNR))
    GLOBALPOSITIONTHISLAYER=$(($(($(($LAYERNR-1))*$(($LAYERTHICKNESS))))+$STARTGLOBALPOS))
    echo "RawStartNr ${STARTFILENRTHISLAYER}" >> ${THISPARAMFILE}
    echo "GlobalPosition ${GLOBALPOSITIONTHISLAYER}" >> ${THISPARAMFILE}
    echo "MicFileBinary MicrostructureBinary_Layer${LAYERNR}.mic" >> ${THISPARAMFILE}
    echo "MicFileText MicrostructureText_Layer${LAYERNR}.mic" >> ${THISPARAMFILE}
    echo "ReducedFileName ${FOLDER}_Layer${LAYERNR}_Reduced/${FILENAME}" >> ${THISPARAMFILE}
    mkdir -p ${FOLDER}_Layer${LAYERNR}_Reduced
    if [[ ${FFSEEDORIENTATIONS} -eq 1 ]]; then
        echo "GrainsFile ${DATADIRECTORY}/GrainsLayer${LAYERNR}.csv" >> ${THISPARAMFILE}
        echo "SeedOrientations ${DATADIRECTORY}/Orientations_Layer${LAYERNR}.txt" >> ${THISPARAMFILE}
    else
        echo "SeedOrientations ${DATADIRECTORY}/Orientations.txt" >> ${THISPARAMFILE}
    fi
    /clhome/TOMO1/PeaksAnalysisHemant/HEDM_V2/NF_HEDM/runSingleLayer.sh ${THISPARAMFILE} ${NCPUS} ${FFSEEDORIENTATIONS} ${PROCESSIMAGES}
done
