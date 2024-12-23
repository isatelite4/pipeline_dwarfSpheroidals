#!/bin/bash
########## Functions ##########

# Functions of general sue

help() {
    echo -e "Pipeline for reducing data from small telescopes"
    echo -e ""
    echo -e "Syntax: pipelineName [-h] configurationFile.conf"
    echo -e "Options:"
    echo -e "    h    Print this help"
    echo -e "Arguments:"
    echo -e "    Configuration file"
    echo -e "\n"
}
export -f help


load_module() {
    local moduleName="$1"  
    errorNumber=8

    if [[ -z "$moduleName" ]]; then
        echo "Error: No module name provided"
        return $errorNumber
    fi

    echo -e "\nLoading $moduleName"
    module load "$moduleName"

    if [[ $? -eq 0 ]]; then
        echo -e "$moduleName loaded successfully"
    else
        echo -e "Failed to load $moduleName"
        # return 1 # I comment this because in the ICR that I'm running they are already loaded so...
    fi
}
export -f load_module

writeTimeOfStepToFile() {
    step=$1
    file=$2

    echo "Step: $step. Start time:  $(date +%D-%T)" >> $file
}
export -f writeTimeOfStepToFile

loadVariablesFromFile() {
  file=$1
  initialShellVariables=$(compgen -v)

  if [[ -f $confFile ]]; then 
    source $confFile
    echo -e "\nVariables loaded from $confFile file"
  else
    errorNumber=1
    echo -e "\nA configuration file has to be provided in order to run the pipeline"  >&2
    echo -e "Exiting with error number: $RED $errorNumber $NOCOLOUR" >&2
    exit $errorNumber
  fi

  allShellVariablesAfterLoadingConfFile=$(compgen -v)
  
  # This code exports only the variables of the configuration file
  for var in $allShellVariablesAfterLoadingConfFile; do
    if ! grep -q "^$var$" <<< "$initialShellVariables"; then
      export "$var"
    fi
  done
  return 0
}
export -f loadVariablesFromFile

outputConfigurationVariablesInformation() {
    data=(
        "·Object name:$objectName"
        "·Right ascension:$ra_gal:[deg]"
        "·Declination:$dec_gal:[deg]"
        "·Keyword for the airmass:$airMassKeyWord"
        "·Keyword for date:$dateHeaderKey"
        "·Root directory to perform the reduction:$ROOTDIR"
        "·Calibration range"
        "  Bright limit:$calibrationBrightLimit:[mag]"
        "  Faint limit:$calibrationFaintLimit:[mag]"
        "The aperture photometry will be done with an aperture of:$numberOfFWHMForPhotometry:[FWHM]"
        "·Saturation threshold:$saturationThreshold:[ADU]"
        "·Gain:$gain:[e-/ADU]"
        "·Approximately size of the field:$sizeOfOurFieldDegrees:[deg]"
        "·Size of the coadd:$coaddSizePx:[px]"
        " "
        "·Common normalisation ring:$USE_COMMON_RING"
        "  If so, the file with the ring specification is:$commonRingDefinitionFile"
        ""
        " Otherwise, parameters for using multiple normalisation rings"
        "  KeyWord to decide the ring to use:$keyWordToDecideRing"
        "  Threshold to decide the ring to use:$keyWordThreshold"
        "  File with the first ring specification:$firstRingDefinitionFile"
        "  Value of the keyword for using the first ring:$keyWordValueForFirstRing"

        "  File with the second ring specification:$secondRingDefinitionFile"
        "  Value of the keyword for using the second ring:$keyWordValueForSecondRing"
        " "
        "·Running flat:$RUNNING_FLAT"
        "  If so, the window size is:$windowSize:[frames]"
        " "
        "·The background is modelled as a constant:$MODEL_SKY_AS_CONSTANT"
        "  If so, the sky estimation method is:$sky_estimation_method"
        "  Otherwise, the polynomial degree is:$polynomialDegree"
        " "
        "·Indices scales for astrometrisation"
        "  Lowest index:$lowestScaleForIndex"
        "  Highest index:$highestScaleForIndex"
        " "
        "·Scale-low parameters for solve-field (astrometry.net):$solve_field_L_Param"
        "·Scale-high parameters for solve-field (astrometry.net):$solve_field_H_Param"
        "·Scale units for parameters for solve-field (astrometry.net):$solve_field_u_Param"
        " "
        "·Filter:$filter"
        "·Pixel scale:$pixelScale:[arcsec/px]"
        "·Detector width:$detectorWidth:[px]"
        "·Detector height:$detectorHeight:[px]"
        " "
        "Parameters for measuring the surface brightness limit"
        "·Exp map fraction:$fractionExpMap"
        "·Area of the SB limit metric:$areaSBlimit: [arcsec]"

        # "Saturation threshold set to:$saturationThreshold"
        # "The size of the field in degrees is:$sizeOfOurFieldDegrees"
        # "The size in px of each side of the coadded image is:$coaddSizePx"
        # "The calibration range is:$calibrationBrightLimit to $calibrationFaintLimit"
        # "The aperture photometry will be done with an aperture of:$numberOfFWHMForPhotometry FWHM"
        # "A common normalisation ring is going to be used?:$USE_COMMON_RING"
        # "The file which contains the ring definition is:$commonRingDefinitionFile"
        # "The running flat is going to be used?:$RUNNING_FLAT"
        # "The running flat will be computed with a window size of:$windowSize"
        # "The indices that will be built for the construction of indices for astrometrisation are"
        # "Lowest index:$lowestScaleForIndex"
        # "Highest index:$highestScaleForIndex"
        # "The background will be modelled as a constant?:$MODEL_SKY_AS_CONSTANT"
        # "If so, the method to model the sky is:$sky_estimation_method"
        # "Otherwise, the polynomial degree is:$polynomialDegree"
    )

    echo -e "Summary of the configuration variables provided for the reduction\n"
    for entry in "${data[@]}"; do
    IFS=":" read -r text value unit <<< "$entry" 
    printf "\t%-60s $ORANGE %-20s $GREEN %-10s $NOCOLOUR\n" "$text" "$value" "$unit"
    done
}
export -f outputConfigurationVariablesInformationl

escapeSpacesFromString() {
    local input="$1"
    escaped_string="${input// /\\ }"
    echo $escaped_string
}
export -f escapeSpacesFromString

checkIfExist_DATEOBS() {
    DATEOBSValue=$1

    if [ "$DATEOBSValue" = "n/a" ]; then
        errorNumber=3
        echo -e "The file $i do not has the $dateHeaderKey, used for sorting the raw files for the pipeline"  >&2
        echo -e "Exiting with error number: $errorNumber"  >&2
        exit $errorNumber
    fi
}
export -f checkIfExist_DATEOBS

getHighestNumberFromFilesInFolder() {
    folderToCheck=$1
    # Find all files, remove non-numeric parts, sort numerically, get the highest number
    highest=$(ls "$folderToCheck" | grep -oE '[0-9]+' | sort -n | tail -1)
    if [ -z "$highest" ]; then
            highest=0
    fi
    echo $highest
}
export -f getHighestNumberFromFilesInFolder

checkIfAllVariablesAreSet() {
    errorNumber=2
    flagToExit=""
    variablesToCheck=(objectName \
                ra_gal \
                dec_gal \
                defaultNumOfCPUs \
                ROOTDIR \
                airMassKeyWord \ 
                dateHeaderKey \
                saturationThreshold \
                gain \
                sizeOfOurFieldDegrees \
                coaddSizePx \
                calibrationBrightLimit \
                calibrationFaintLimit \
                numberOfFWHMForPhotometry \
                USE_COMMON_RING \
                commonRingDefinitionFile \
                keyWordToDecideRing
                keyWordThreshold
                firstRingDefinitionFile
                keyWordValueForFirstRing
                secondRingDefinitionFile
                keyWordValueForSecondRing
                RUNNING_FLAT \
                windowSize \
                halfWindowSize \
                MODEL_SKY_AS_CONSTANT \
                sky_estimation_method \
                polynomialDegree \
                filter \
                pixelScale \
                detectorWidth \
                detectorHeight \ 
                lowestScaleForIndex \
                highestScaleForIndex \ 
                solve_field_L_Param \
                solve_field_H_Param \
                solve_field_u_Param \ 
                numberOfStdForBadFrames
                fractionExpMap\
                areaSBlimit)

    echo -e "\n"
    for currentVar in ${variablesToCheck[@]}; do
        [[ -z ${!currentVar} ]] && echo "${currentVar} variable not defined" && flagToExit=true
    done

    # I exit here and not when I find the variable missing because I want to show all the messages of "___ variable not defined", so the user knows all the variables that are needed
    [[ $flagToExit ]] && echo -e "Exiting with error number: $errorNumber" && exit $errorNumber
}
export -f checkIfAllVariablesAreSet




# Functions used in Flat
maskImages() {
    inputDirectory=$1
    masksDirectory=$2
    outputDirectory=$3
    useCommonRing=$4
    keyWordToDecideRing=$5


    for a in $(seq 1 $n_exp); do
        base="$objectName"-Decals-"$filter"_n"$currentNight"_f"$a"_ccd"$h".fits
        i=$inputDirectory/$base
        out=$outputDirectory/$base
        astarithmetic $i -h1 $masksDirectory/$base -hDETECTIONS 1 eq nan where float32 -o $out -q

        propagateKeyword $i $airMassKeyWord $out 
        # If we are not doing a normalisation with a common ring we propagate the keyword that will be used to decide
        # which ring is to be used. This way we can check this value in a comfortable way in the normalisation section
        if [ "$useCommonRing" = false ]; then
            propagateKeyword $i $keyWordToDecideRing $out
        fi
    done

}
export -f maskImages

writeKeywordToFits() {
    fitsFile=$1
    header=$2
    keyWord=$3
    value=$4

    astfits --write=$keyWord,$value $fitsFile -h$header
}
export -f writeKeywordToFits

propagateKeyword() {
    image=$1
    keyWordToPropagate=$2
    out=$3

    variableToDecideRingToNormalise=$(gethead $image $keyWordToPropagate)
    eval "astfits --write=$keyWordToPropagate,$variableToDecideRingToNormalise $out -h1" 
}
export -f propagateKeyword

addkeywords() {
    local fits_file=$1
    shift
    local -n keys_array=$1
    local -n values_array=$2

    if [[ -z "$fits_file" || ${#keys_array[@]} -eq 0 || ${#values_array[@]} -eq 0 ]]; then
        errorNumber=7
        echo -e "Error in 'addkeywords', some argument is empty"
        echo -e "Exiting with error number: $RED $errorNumber $NOCOLOUR" >&2
        exit $errorNumber 
    fi

    if [[ ${#keys_array[@]} -ne ${#values_array[@]} ]]; then
        echo -e "Error in 'addkeywords', the length of keys and values does not match"
        echo -e "Exiting with error number: $RED $errorNumber $NOCOLOUR" >&2
        exit $errorNumber   
    fi

    for i in "${!keys_array[@]}"; do
        local key="${keys_array[$i]}"
        local value="${values_array[$i]}"

        writeKeywordToFits $fits_file 1 "$key" "$value"
    done
}
export -f addkeywords


getMedianValueInsideRing() {
    i=$1
    commonRing=$2
    doubleRing_first=$3
    doubleRing_second=$4
    useCommonRing=$5
    keyWordToDecideRing=$6
    keyWordThreshold=$7
    keyWordValueForFirstRing=$8
    keyWordValueForSecondRing=$9


    if [ "$useCommonRing" = true ]; then
            # Case when we have one common normalisation ring
            me=$(astarithmetic $i -h1 $commonRing -h1 0 eq nan where medianvalue --quiet)
    else
        # Case when we do NOT have one common normalisation ring
        # All the following logic is to decide which normalisation ring apply
        variableToDecideRingToNormalise=$(gethead $i $keyWordToDecideRing)
        firstRingLowerBound=$(echo "$keyWordValueForFirstRing - $keyWordThreshold" | bc)
        firstRingUpperBound=$(echo "$keyWordValueForFirstRing + $keyWordThreshold" | bc)
        secondRingLowerBound=$(echo "$keyWordValueForSecondRing - $keyWordThreshold" | bc)
        secondRingUpperBound=$(echo "$keyWordValueForSecondRing + $keyWordThreshold" | bc)

        if (( $(echo "$variableToDecideRingToNormalise >= $firstRingLowerBound" | bc -l) )) && (( $(echo "$variableToDecideRingToNormalise <= $firstRingUpperBound" | bc -l) )); then
            me=$(astarithmetic $i -h1 $doubleRing_first -h1 0 eq nan where medianvalue --quiet)
        elif (( $(echo "$variableToDecideRingToNormalise >= $secondRingLowerBound" | bc -l) )) && (( $(echo "$variableToDecideRingToNormalise <= $secondRingUpperBound" | bc -l) )); then
            me=$(astarithmetic $i -h1 $doubleRing_second -h1 0 eq nan where medianvalue --quiet)
        else
            errorNumber=4
            echo -e "\nMultiple normalisation ring have been tried to be used. The keyword selection value of one has not matched with the ranges provided" >&2
            echo -e "Exiting with error number: $RED $errorNumber $NOCOLOUR" >&2
            exit $errorNumber 
        fi
    fi

    echo $me # This is for "returning" the value
}
export -f getMedianValueInsideRing

getStdValueInsideRing() {
    i=$1
    commonRing=$2
    doubleRing_first=$3
    doubleRing_second=$4
    useCommonRing=$5
    keyWordToDecideRing=$6
    keyWordThreshold=$7
    keyWordValueForFirstRing=$8
    keyWordValueForSecondRing=$9

    if [ "$useCommonRing" = true ]; then
            # Case when we have one common normalisation ring
            std=$(astarithmetic $i -h1 $commonRing -h1 0 eq nan where stdvalue --quiet)
    else
        # Case when we do NOT have one common normalisation ring
        # All the following logic is to decide which normalisation ring apply
        variableToDecideRingToNormalise=$(gethead $i $keyWordToDecideRing)
        firstRingLowerBound=$(echo "$keyWordValueForFirstRing - $keyWordThreshold" | bc)
        firstRingUpperBound=$(echo "$keyWordValueForFirstRing + $keyWordThreshold" | bc)
        secondRingLowerBound=$(echo "$keyWordValueForSecondRing - $keyWordThreshold" | bc)
        secondRingUpperBound=$(echo "$keyWordValueForSecondRing + $keyWordThreshold" | bc)

        if (( $(echo "$variableToDecideRingToNormalise >= $firstRingLowerBound" | bc -l) )) && (( $(echo "$variableToDecideRingToNormalise <= $firstRingUpperBound" | bc -l) )); then
            std=$(astarithmetic $i -h1 $doubleRing_first -h1 0 eq nan where stdvalue --quiet)
        elif (( $(echo "$variableToDecideRingToNormalise >= $secondRingLowerBound" | bc -l) )) && (( $(echo "$variableToDecideRingToNormalise <= $secondRingUpperBound" | bc -l) )); then
            std=$(astarithmetic $i -h1 $doubleRing_second -h1 0 eq nan where stdvalue --quiet)
        else
            errorNumber=5
            echo -e "\nMultiple normalisation ring have been tried to be used. The keyword selection value of one has not matched with the ranges provided" >&2
            echo -e "Exiting with error number: $RED $errorNumber $NOCOLOUR" >&2
            exit $errorNumber 
        fi
    fi

    echo $std # This is for "returning" the value
}
export -f getStdValueInsideRing


normaliseImagesWithRing() {
    imageDir=$1
    outputDir=$2
    useCommonRing=$3

    commonRing=$4
    doubleRing_first=$5
    doubleRing_second=$6
    
    keyWordToDecideRing=$7
    keyWordThreshold=$8
    keyWordValueForFirstRing=$9
    keyWordValueForSecondRing=${10}

    for a in $(seq 1 $n_exp); do
        base="$objectName"-Decals-"$filter"_n"$currentNight"_f"$a"_ccd"$h".fits
        i=$imageDir/$base
        out=$outputDir/$base

        me=$(getMedianValueInsideRing $i $commonRing  $doubleRing_first $doubleRing_second $useCommonRing $keyWordToDecideRing $keyWordThreshold $keyWordValueForFirstRing $keyWordValueForSecondRing)
        astarithmetic $i -h1 $me / -o $out
        propagateKeyword $i $airMassKeyWord $out 
    done
}
export -f normaliseImagesWithRing

calculateFlat() {
    flatName="$1"
    shift
    filesToUse="$@"
    numberOfFiles=$#

    # ****** Decision note *******
    # The rejection parameters for the construction of the flat has been chosen to be 2 sigmas
    # The running flat implies that we only have fewer frames for the flat (in our case 11 for example)
    # So we have to be a little bit aggresive in order to be able to remove the outliers
    sigmaValue=2
    iterations=10
    astarithmetic $filesToUse $numberOfFiles $sigmaValue $iterations sigclip-median -g1 -o $flatName
}
export -f calculateFlat

calculateRunningFlat() {
    normalisedDir=$1
    outputDir=$2
    doneFile=$3
    iteration=$4

    fileArray=()
    fileArray=( $(ls -v $normalisedDir/*Decals-"$filter"_n*_f*_ccd"$h".fits) )
    fileArrayLength=( $(ls -v $normalisedDir/*Decals-"$filter"_n*_f*_ccd"$h".fits | wc -l) )

    lefFlatFiles=("${fileArray[@]:0:$windowSize}")
    echo "Computing left flat - iteration $iteration"
    calculateFlat "$outputDir/flat-it"$iteration"_"$filter"_n"$currentNight"_left_ccd"$h".fits" "${lefFlatFiles[@]}"
    rightFlatFiles=("${fileArray[@]:(fileArrayLength-$windowSize):fileArrayLength}")
    echo "Computing right flat - iteration $iteration"
    calculateFlat "$outputDir/flat-it"$iteration"_"$filter"_n"$currentNight"_right_ccd"$h".fits" "${rightFlatFiles[@]}"

    echo "Computing non-common flats - iteration $iteration"

    for a in $(seq 1 $n_exp); do
        if [ "$a" -gt "$((halfWindowSize + 1))" ] && [ "$((a))" -lt "$(($n_exp - $halfWindowSize))" ]; then
            leftLimit=$(( a - $halfWindowSize - 1))
            calculateFlat "$outputDir/flat-it"$iteration"_"$filter"_n"$currentNight"_f"$a"_ccd"$h".fits" "${fileArray[@]:$leftLimit:$windowSize}"
        fi
    done
    echo done > $doneFile
}
export -f calculateRunningFlat

divideImagesByRunningFlats(){
    imageDir=$1
    outputDir=$2
    flatDir=$3
    flatDone=$4

    for a in $(seq 1 $n_exp); do
        base="$objectName"-Decals-"$filter"_n"$currentNight"_f"$a"_ccd"$h".fits
        i=$imageDir/$base
        out=$outputDir/$base

        if [ "$a" -le "$((halfWindowSize + 1))" ]; then
            flatToUse=$flatDir/flat-it*_"$filter"_n"$currentNight"_left_ccd"$h".fits
        elif [ "$a" -ge "$((n_exp - halfWindowSize))" ]; then
            flatToUse=$flatDir/flat-it*_"$filter"_n"$currentNight"_right_ccd"$h".fits
        else
            flatToUse=$flatDir/flat-it*_"$filter"_n"$currentNight"_f"$a"_ccd"$h".fits
        fi
            astarithmetic $i -h1 $flatToUse -h1 / -o $out
            # This step can probably be removed
            astfits $i --copy=1 -o$out

        propagateKeyword $i $airMassKeyWord $out 
    done
    echo done > $flatDone
}
export -f divideImagesByRunningFlats

divideImagesByWholeNightFlat(){
    imageDir=$1
    outputDir=$2
    flatToUse=$3
    flatDone=$4

    for a in $(seq 1 $n_exp); do
        base="$objectName"-Decals-"$filter"_n"$currentNight"_f"$a"_ccd"$h".fits
        i=$imageDir/$base
        out=$outputDir/$base

        astarithmetic $i -h1 $flatToUse -h1 / -o $out
        propagateKeyword $i $airMassKeyWord $out 
    done
    echo done > $flatDone
}
export -f divideImagesByWholeNightFlat

runNoiseChiselOnFrame() {
baseName=$1
inputFileDir=$2
outputDir=$3
noiseChiselParams=$4

imageToUse=$inputFileDir/$baseName
output=$outputDir/$baseName
echo astnoisechisel $imageToUse $noiseChiselParams -o $output
astnoisechisel $imageToUse $noiseChiselParams -o $output
}
export -f runNoiseChiselOnFrame

# Functions for Warping the frames
getCentralCoordinate(){
    image=$1

    NAXIS1=$(gethead $image NAXIS1)
    NAXIS2=$(gethead $image NAXIS2)
    # Calculate the center pixel coordinates
    center_x=$((NAXIS1 / 2))
    center_y=$((NAXIS2 / 2))

    # Use xy2sky to get the celestial coordinates of the center pixel
    imageCentre=$( xy2sky $image $center_x $center_y )
    echo $imageCentre
}
export -f getCentralCoordinate

warpImage() {
    imageToSwarp=$1
    entireDir_fullGrid=$2
    entiredir=$3
    ra=$4
    dec=$5
    coaddSizePx=$6

    # ****** Decision note *******
    # We need to regrid the frames into the final coadd grid. But if we do this right now we will be processing
    # frames too big (which are mostly Nans) and the noisechisel routine takes a looot of time
    # The approach taken is to move the frame to that grid, and then crop it to the dimension of the data itself
    # We need to store both. I have tried to store the small one and then warp it again to the big grid, it's more time consuming
    # and the nan wholes grow so we end up with less light in the final coadd.

    # Parameters for identifing our frame in the full grid
    currentIndex=$(basename $imageToSwarp .fits)

    tmpFile1=$entiredir"/$currentIndex"_temp1.fits
    frameFullGrid=$entireDir_fullGrid/entirecamera_$currentIndex.fits

    # Resample into the final grid
    # Be careful with how do you have to call this package, because in the SIE sofware is "SWarp" and in the TST-ICR is "swarp"
    swarp -c $swarpcfg $imageToSwarp -CENTER $ra,$dec -IMAGE_SIZE $coaddSizePx,$coaddSizePx -IMAGEOUT_NAME $entiredir/"$currentIndex"_swarp1.fits -WEIGHTOUT_NAME $entiredir/"$currentIndex"_swarp_w1.fits -SUBTRACT_BACK N -PIXEL_SCALE $pixelScale -PIXELSCALE_TYPE    MANUAL
    
    # Mask bad pixels
    astarithmetic $entiredir/"$currentIndex"_swarp_w1.fits -h0 set-i i i 0 lt nan where -o$tmpFile1
    astarithmetic $entiredir/"$currentIndex"_swarp1.fits -h0 $tmpFile1 -h1 0 eq nan where -o$frameFullGrid

    regionOfDataInFullGrid=$(python3 $pythonScriptsPath/getRegionToCrop.py $frameFullGrid 1)
    read row_min row_max col_min col_max <<< "$regionOfDataInFullGrid"
    astcrop $frameFullGrid --polygon=$col_min,$row_min:$col_max,$row_min:$col_max,$row_max:$col_min,$row_max --mode=img  -o $entiredir/entirecamera_"$currentIndex".fits --quiet

    rm $entiredir/"$currentIndex"_swarp_w1.fits $entiredir/"$currentIndex"_swarp1.fits $tmpFile1 
}
export -f warpImage

removeBadFramesFromReduction() {
    sourceToRemoveFiles=$1
    destinationDir=$2
    badFilesWarningDir=$3
    badFilesWarningFile=$4

    filePath=$badFilesWarningDir/$badFilesWarningFile

    while IFS= read -r file_name; do
        file_name=$(basename "$file_name")
        fileName="${file_name%.*}".fits
        mv $sourceToRemoveFiles/$fileName $destinationDir/$fileName
    done < "$filePath"
}
export -f removeBadFramesFromReduction

# Functions for compute and subtract sky from frames
computeSkyForFrame(){
    base=$1
    entiredir=$2
    noiseskydir=$3
    constantSky=$4
    constantSkyMethod=$5
    polyDegree=$6
    inputImagesAreMasked=$7
    ringDir=$8
    useCommonRing=$9
    keyWordToDecideRing=${10}
    keyWordThreshold=${11}
    keyWordValueForFirstRing=${12}
    keyWordValueForSecondRing=${13}

    i=$entiredir/$1

    # ****** Decision note *******
    # Here we have implemented two possibilities. Either the background is estimated by a constant or by a polynomial.
    # If it is a constant we store the fileName, the background value and the std. This is implemented this way because we
    # need the background to subtract but also later the std for weighing the frames
    # If it is a polynomial we only use it to subtract the background (the weighing is always with a constat) so we only store
    # the coefficients of the polynomial.
    # 
    # Storing this values is also relevant for checking for potential bad frames
    out=$(echo $base | sed 's/.fits/.txt/')

    if [ "$constantSky" = true ]; then  # Case when we subtract a constant
        # Here we have two possibilities
        # Estimate the background within the normalisation ring or using noisechisel

        # The problem is that I can't use the same ring/s as in the normalisation because here we have warped and cropped the images... So I create a new normalisation ring from the centre of the images
        # I cannot even create a common ring for all, because they are cropped based on the number of non-nan (depending on the vignetting and how the NAN are distributed), so i create a ring per image
        # For that reason the subtraction of the background using the ring is always using a ring centered in the frame
        # More logic should be implemented to use the normalisation ring(s) and recover them after the warping and cropping
        if [ "$constantSkyMethod" = "ring" ]; then

            # Mask the image if they are not already masked
            if ! [ "$inputImagesAreMasked" = true ]; then
                tmpMask=$(echo $base | sed 's/.fits/_mask.fits/')
                tmpMaskedImage=$(echo $base | sed 's/.fits/_masked.fits/')
                astnoisechisel $i $noisechisel_param -o $noiseskydir/$tmpMask
                astarithmetic $i -h1 $noiseskydir/$tmpMask -h1 1 eq nan where float32 -o $noiseskydir/$tmpMaskedImage --quiet
                imageToUse=$noiseskydir/$tmpMaskedImage
                rm -f $noiseskydir/$tmpMask
            else
                imageToUse=$i
            fi

            # We generate the ring (we cannot use the normalisation ring because we have warped and cropped) and compute the background value within it
            tmpRingDefinition=$(echo $base | sed 's/.fits/_ring.txt/')
            tmpRingFits=$(echo $base | sed 's/.fits/_ring.fits/')

            naxis1=$(fitsheader $imageToUse | grep "NAXIS1" | awk '{print $3}')
            naxis2=$(fitsheader $imageToUse | grep "NAXIS2" | awk '{print $3}')
            half_naxis1=$(echo "$naxis1 / 2" | bc)
            half_naxis2=$(echo "$naxis2 / 2" | bc)
            echo "1 $half_naxis1 $half_naxis2 6 1150 1 1 1 1 1" > $ringDir/$tmpRingDefinition
            astmkprof --background=$imageToUse  -h1 --mforflatpix --mode=img --type=uint8 --circumwidth=200 --clearcanvas -o $ringDir/$tmpRingFits $ringDir/$tmpRingDefinition

            me=$(getMedianValueInsideRing $imageToUse  $ringDir/$tmpRingFits "" "" true $keyWordToDecideRing $keyWordThreshold $keyWordValueForFirstRing $keyWordValueForSecondRing)
            std=$(getStdValueInsideRing $imageToUse $ringDir/$tmpRingFits "" "" true $keyWordToDecideRing $keyWordThreshold $keyWordValueForFirstRing $keyWordValueForSecondRing)
            echo "$base $me $std" > $noiseskydir/$out

            rm $ringDir/$tmpRingDefinition
            rm $ringDir/$tmpRingFits

        elif [ "$constantSkyMethod" = "noisechisel" ]; then
            sky=$(echo $base | sed 's/.fits/_sky.fits/')

            # The sky substraction is done by using the --checksky option in noisechisel
            astnoisechisel $i --tilesize=20,20 --interpnumngb=5 --dthresh=0.1 --snminarea=2 --checksky $noisechisel_param -o $noiseskydir/$base

            mean=$(aststatistics $noiseskydir/$sky -hSKY --sigclip-mean)
            std=$(aststatistics $noiseskydir/$sky -hSTD --sigclip-mean)
            echo "$base $mean $std" > $noiseskydir/$out
            rm -f $noiseskydir/$sky
        else
            errorNumber=6
            echo -e "\nAn invalid value for the sky_estimation_method was provided" >&2
            echo -e "Exiting with error number: $RED $errorNumber $NOCOLOUR" >&2
            exit $errorNumber
        fi

    else
        # Case when we model a plane
        noiseOutTmp=$(echo $base | sed 's/.fits/_sky.fits/')
        maskTmp=$(echo $base | sed 's/.fits/_masked.fits/')
        planeOutput=$(echo $base | sed 's/.fits/_poly.fits/')
        planeCoeffFile=$(echo $base | sed 's/.fits/.txt/')

        # This conditional allows us to introduce the images already masked (masked with the mask of the coadd) in the second and next iterations
        if ! [ "$inputImagesAreMasked" = true ]; then
            astnoisechisel $i --tilesize=20,20 --interpnumngb=5 --dthresh=0.1 --snminarea=2 --checksky $noisechisel_param -o $noiseskydir/$base
            astarithmetic $i -h1 $noiseskydir/$noiseOutTmp -hDETECTED 1 eq nan where -q float32 -o $noiseskydir/$maskTmp
            python3 $pythonScriptsPath/surface-fit.py -i $noiseskydir/$maskTmp -o $noiseskydir/$planeOutput -d $polyDegree -f $noiseskydir/$planeCoeffFile
        else
            python3 $pythonScriptsPath/surface-fit.py -i $i -o $noiseskydir/$planeOutput -d $polyDegree -f $noiseskydir/$planeCoeffFile
        fi

        rm -f $noiseskydir/$noiseOutTmp
        rm -f $noiseskydir/$maskTmp
    fi
}
export -f computeSkyForFrame



computeSky() {
    framesToUseDir=$1
    noiseskydir=$2
    noiseskydone=$3
    constantSky=$4
    constantSkyMethod=$5
    polyDegree=$6
    inputImagesAreMasked=$7
    ringDir=$8
    useCommonRing=$9
    keyWordToDecideRing=${10}
    keyWordThreshold=${11}
    keyWordValueForFirstRing=${12}
    keyWordValueForSecondRing=${13}
    

    if ! [ -d $noiseskydir ]; then mkdir $noiseskydir; fi
    if [ -f $noiseskydone ]; then
        echo -e "\n\tScience images are 'noisechiseled' for constant sky substraction for extension $h\n"
    else
        framesToComputeSky=()
        for a in $(seq 1 $totalNumberOfFrames); do
            base="entirecamera_"$a.fits
            framesToComputeSky+=("$base")
        done

        printf "%s\n" "${framesToComputeSky[@]}" | parallel -j "$num_cpus" computeSkyForFrame {} $framesToUseDir $noiseskydir $constantSky $constantSkyMethod $polyDegree $inputImagesAreMasked $ringDir $useCommonRing $keyWordToDecideRing $keyWordThreshold $keyWordValueForFirstRing $keyWordValueForSecondRing
        echo done > $noiseskydone
    fi
}

subtractSkyForFrame() {
    a=$1
    directoryWithSkyValues=$2
    framesToSubtract=$3
    directoryToStoreSkySubtracted=$4
    constantSky=$5

    base="entirecamera_"$a.fits
    input=$framesToSubtract/$base
    output=$directoryToStoreSkySubtracted/$base

    if [ "$constantSky" = true ]; then
        i=$directoryWithSkyValues/"entirecamera_"$a.txt
        me=$(awk 'NR=='1'{print $2}' $i)
        astarithmetic $input -h1 $me - -o$output;
    else
        i=$directoryWithSkyValues/"entirecamera_"$a"_poly.fits"

        NAXIS1_image=$(gethead $input NAXIS1); NAXIS2_image=$(gethead $input NAXIS2)
        NAXIS1_plane=$(gethead $i NAXIS1); NAXIS2_plane=$(gethead $i NAXIS2)

        if [[ "$NAXIS1_image" == "$NAXIS1_plane" ]] && [[ "$NAXIS2_image" == "$NAXIS2_plane" ]]; then
            astarithmetic $input -h1 $i -h1 - -o$output
        else
            python3 $pythonScriptsPath/moveSurfaceFitToFullGrid.py $input $i 1 $NAXIS1_image $NAXIS2_image $directoryToStoreSkySubtracted/"planeToSubtract_"$a".fits"
            astarithmetic $input -h1 $directoryToStoreSkySubtracted/"planeToSubtract_"$a".fits" -h1 - -o$output
            rm $directoryToStoreSkySubtracted/"planeToSubtract_"$a".fits"
        fi

    fi
}
export -f subtractSkyForFrame

subtractSky() {
    framesToSubtract=$1
    directoryToStoreSkySubtracted=$2
    directoryToStoreSkySubtracteddone=$3
    directoryWithSkyValues=$4
    constantSky=$5


    if ! [ -d $directoryToStoreSkySubtracted ]; then mkdir $directoryToStoreSkySubtracted; fi
    if [ -f $directoryToStoreSkySubtracteddone ]; then
        echo -e "\n\tSky substraction is already done for the science images\n"
    else
    framesToSubtractSky=()
    for a in $(seq 1 $totalNumberOfFrames); do
            framesToSubtractSky+=("$a")            
    done
    printf "%s\n" "${framesToSubtractSky[@]}" | parallel -j "$num_cpus" subtractSkyForFrame {} $directoryWithSkyValues $framesToSubtract $directoryToStoreSkySubtracted $constantSky
    echo done > $directoryToStoreSkySubtracteddone
    fi
}


# Functions for decals data
# The function that is to be used (the 'public' function using OOP terminology)
# Is 'prepareDecalsDataForPhotometricCalibration'
getBricksWhichCorrespondToFrame() {
    frame=$1
    frameBrickMapFile=$2

    bricks=$( awk -v var=$(basename $frame) '$1==var { match($0, /\[([^]]+)\]/, arr); print arr[1] }' $frameBrickMapFile )
    IFS=", "
    read -r -a array <<< $bricks

    # Remove the single quotes from elements
    for ((i=0; i<${#array[@]}; i++)); do
            array[$i]=${array[$i]//\'/}
    done
    echo "${array[@]}"
}
export -f getBricksWhichCorrespondToFrame

getParametersFromHalfMaxRadius() {
    image=$1
    gaiaCatalogue=$2
    kernel=$3
    tmpFolder=$4

    # The output of the commands are redirected to /dev/null because otherwise I cannot return the median and std.
    # Quite uncomfortable the return way of bash. Nevertheless, the error output is not modified so if an instruction fails we still get the error message.
    astconvolve $image --kernel=$kernel --domain=spatial --output=$tmpFolder/convolved.fits 1>/dev/null
    astnoisechisel $image -h1 -o $tmpFolder/det.fits --convolved=$tmpFolder/convolved.fits --tilesize=20,20 --detgrowquant=0.95 --erode=4 1>/dev/null
    astsegment $tmpFolder/det.fits -o $tmpFolder/seg.fits --snquant=0.1 --gthresh=-10 --objbordersn=0    --minriverlength=3 1>/dev/null
    astmkcatalog $tmpFolder/seg.fits --ra --dec --magnitude --half-max-radius --sum --clumpscat -o $tmpFolder/decals.txt --zeropoint=22.5 1>/dev/null
    astmatch $tmpFolder/decals_c.txt --hdu=1    $BDIR/catalogs/"$objectName"_Gaia_eDR3.fits --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=$toleranceForMatching/3600 --outcols=bRA,bDEC,aHALF_MAX_RADIUS,aMAGNITUDE -o $tmpFolder/match_decals_gaia.txt 1>/dev/null

    numOfStars=$( cat $tmpFolder/match_decals_gaia.txt | wc -l )
    median=$( asttable $tmpFolder/match_decals_gaia.txt -h1 -c3 --noblank=MAGNITUDE | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-median )
    std=$( asttable $tmpFolder/match_decals_gaia.txt -h1 -c3 --noblank=MAGNITUDE | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-std )
    rm $tmpFolder/*
    echo $median $std $numOfStars
}


downloadDecalsData() {
    referenceImagesForMosaic=$1
    mosaicDir=$2
    decalsImagesDir=$3
    frameBrickCorrespondenceFile=$4
    
    filters=$5
    ringFile=$6

    echo -e "\n·Downloading Decals bricks"

    donwloadMosaicDone=$mosaicDir/decalsImages/done_downloads.txt
    if ! [ -d $mosaicDir ]; then mkdir $mosaicDir; fi
    if ! [ -d $decalsImagesDir ]; then mkdir $decalsImagesDir; fi
    if [ -f $donwloadMosaicDone ]; then
        echo -e "\n\tMosaic images already downloaded\n"
    else
        rm $frameBrickCorrespondenceFile # Remove the brick map. This is done to avoid problems with files of previous executions

        # Note about paralellisation on this step
        # Each frame has 4 DECaLS bricks associated to download. If I paralellise I will download (or try to download) the same brick
        # multiple times. The donwloadBricksForFrame has implemented the logic for not downloading a brick already downloaded, but I'm afraid
        # of race conditions that could occur. Instead, what is being done right now is that the 4 bricks of each frame are downloaded 
        # using multithreads because we are sure that these 4 are different.

        for a in $(seq 1 $totalNumberOfFrames); do
            base="entirecamera_$a".fits
            echo "Downloading decals bricks for image: " $base " for filters: " $filters
            bricksOfTheFrame=$(python3 $pythonScriptsPath/downloadBricksForFrame.py $referenceImagesForMosaic/$base $ringFile $filters $decalsImagesDir)
            echo $base $bricksOfTheFrame >> $frameBrickCorrespondenceFile         # Creating the map between frames and bricks to recover it in the photometric calibration
        done
        echo done > $donwloadMosaicDone
    fi
}

addTwoFiltersAndDivideByTwo() {
    decalsImagesDir=$1
    filter1=$2
    filter2=$3

    addBricksDone=$mosaicDir/decalsImages/done_adding.txt
    if [ -f $addBricksDone ]; then
        echo -e "\nDecals '$filter1' and '$filter2' bricks are already added\n"
    else
        for file in "$decalsImagesDir"/*_$filter1.fits; do
            # The following lines depend on the name of the decals images, which is defined in the python script "./decals_GetAndDownloadBricks.py"
            brickName=$(basename "$file" | cut -d '_' -f3)
            filter1File="decal_image_"$brickName"_$filter1.fits"
            filter2File="decal_image_"$brickName"_$filter2.fits"

            echo -e "Adding the files " $filter1File " and the file " $filter2File
            astarithmetic $decalsImagesDir/$filter1File -h1 $decalsImagesDir/$filter2File -h1 + 2 / -o$decalsImagesDir/"decal_image_"$brickName"_"$filter1"+"$filter2"_div2.fits"
        done
        echo done > $addBricksDone
    fi
}
export -f addTwoFiltersAndDivideByTwo

warpDecalsBrick() {
    a=$1
    swarpedImagesDir=$2
    decalsImagesDir=$3
    scaleFactor=$4
    swarpcfg=$5
    ra=$6
    dec=$7
    mosaicSize=$8
    decalsPxScale=$9

    decalsImage=$decalsImagesDir/$a
    downSampledImages="$swarpedImagesDir/originalGrid_$(basename $a)"

    astwarp $decalsImage --scale=$scaleFactor -o $downSampledImages

    swarp -c $swarpcfg $downSampledImages -CENTER $ra,$dec -IMAGE_SIZE $mosaicSize,$mosaicSize -IMAGEOUT_NAME $swarpedImagesDir/"$a"_swarp1.fits \
                        -WEIGHTOUT_NAME $swarpedImagesDir/"$a"_swarp_w1.fits -SUBTRACT_BACK N -PIXEL_SCALE $decalsPxScale -PIXELSCALE_TYPE MANUAL
    astarithmetic $swarpedImagesDir/"$a"_swarp_w1.fits -h0 set-i i i 0 lt nan where -o$swarpedImagesDir/"$a"_temp1.fits
    astarithmetic $swarpedImagesDir/"$a"_swarp1.fits -h0 $swarpedImagesDir/"$a"_temp1.fits -h1 0 eq nan where -o$swarpedImagesDir/commonGrid_"$(basename $a)"

    rm $swarpedImagesDir/"$a"_swarp_w1.fits $swarpedImagesDir/"$a"_swarp1.fits $swarpedImagesDir/"$a"_temp1.fits
}
export -f warpDecalsBrick

buildDecalsMosaic() {
    # We only need the mosaic in order to download the gaia catalogue. That's why downgrade the bricks
    # Values for original decals resolution. As a reminder decals original pxScale 0.2626 arcsec/px

    mosaicDir=$1
    decalsImagesDir=$2
    swarpcfg=$3
    ra=$4
    dec=$5
    filter=$6
    swarpedImagesDir=$7
    dataPixelScale=$8 # Pixel scale of our data. In order to do realisticly we should downgrade decals data to the same resolution as our data
    sizeOfOurFieldDegrees=$9 # Estimation of how big is our field

    originalDecalsPxScale=0.262 # arcsec/px

    buildMosaicDone=$swarpedImagesDir/done_t.xt
    if ! [ -d $swarpedImagesDir ]; then mkdir $swarpedImagesDir; fi
    if [ -f $buildMosaicDone ]; then
        echo -e "\n\tMosaic already built\n"
    else
        decalsPxScale=$dataPixelScale
        mosaicSize=$(echo "($sizeOfOurFieldDegrees * 3600) / $decalsPxScale" | bc)

        # This depends if you want to calibrate with the original resolution (recommended) or downgrade it to your data resolution
        scaleFactor=1 # Original resolution
        # scaleFactor=$(awk "BEGIN {print $originalDecalsPxScale / $dataPixelScale}") # Your data resolution

        if [ "$filter" = "lum" ]; then
            bricks=$(ls -v $decalsImagesDir/*_g+r_div2.fits)
        elif [ "$filter" = "i" ]; then
            bricks=$(ls -v $decalsImagesDir/*_r+z_div2.fits)
        else
            bricks=$(ls -v $decalsImagesDir/*$filter.fits)
        fi

        brickList=()
        for a in $bricks; do
            brickList+=("$( basename $a )")
        done
        printf "%s\n" "${brickList[@]}" | parallel -j "$num_cpus" warpDecalsBrick {} $swarpedImagesDir $decalsImagesDir $scaleFactor $swarpcfg $ra $dec $mosaicSize $decalsPxScale

        sigma=2
        astarithmetic $(ls -v $swarpedImagesDir/commonGrid*.fits) $(ls -v $swarpedImagesDir/commonGrid*.fits | wc -l) -g1 $sigma 0.2 sigclip-median -o $mosaicDir/mosaic.fits
        echo done > $buildMosaicDone
    fi
}

downloadGaiaCatalogueForField() {
    mosaicDir=$1

    mos=$mosaicDir/mosaic.fits
    ref=$mos

    retcatdone=$BDIR/downloadedGaia_done_"$n".txt
    if [ -f $retcatdone ]; then
            echo -e "\n\tgaia dr3 catalog retrived\n"
    else
        astquery gaia --dataset=edr3 --overlapwith=$ref --column=ra,dec,phot_g_mean_mag,parallax,parallax_error,pmra,pmra_error,pmdec,pmdec_error    -o$BDIR/catalogs/"$objectName"_Gaia_eDR3_.fits
        asttable $BDIR/catalogs/"$objectName"_Gaia_eDR3_.fits -c1,2,3 -c'arith $4 abs' -c'arith $5 3 x' -c'arith $6 abs' -c'arith $7 3 x' -c'arith $8 abs' -c'arith $9 3 x' --noblank=4 -otmp.txt

        # I have explored 3 different ways of selecting good stars. 
        # From the most restrictive to the less restrictive:

        # # Here I demand that the gaia object fulfills simultaneously that:
        # # 1.- Parallax > 3 times its error
        # # 2.- Proper motion (ra) > 3 times its error
        # # 3.- Proper motion (dec) > 3 times its error
        # asttable tmp.txt -c1,2,3 -c'arith $4 $4 $5 gt 1000 where' -c'arith $6 $6 $7 gt 1000 where' -c'arith $8 $8 $9 gt 1000 where'    -otest_.txt
        # asttable test_.txt -c1,2,3 -c'arith $4 $5 + $6 +' -otest1.txt
        # asttable test1.txt -c1,2,3 --range=ARITH_2,2999,3001 -o $BDIR/catalogs/"$objectName"_Gaia_eDR3.fits

        # # Here I only demand that the parallax is > 3 times its error
        # asttable tmp.txt -c1,2,3 -c'arith $4 $4 $5 gt 1000 where' -otest_.txt
        # asttable test_.txt -c1,2,3 --range=ARITH_2,999,1001 -o $BDIR/catalogs/"$objectName"_Gaia_eDR3.fits


        # Here I  demand that the parallax OR a proper motion is > 3 times its error
        asttable tmp.txt -c1,2,3 -c'arith $4 $4 $5 gt 1000 where' -c'arith $6 $6 $7 gt 1000 where' -c'arith $8 $8 $9 gt 1000 where'    -otest_.txt
        asttable test_.txt -c1,2,3 -c'arith $4 $5 + $6 +' -otest1.txt
        asttable test1.txt -c1,2,3 --range=ARITH_2,999,3001 -o $BDIR/catalogs/"$objectName"_Gaia_eDR3.fits
        
        rm test1.txt tmp.txt $BDIR/catalogs/"$objectName"_Gaia_eDR3_.fits test_.txt
        echo done > $retcatdone
    fi
}

downloadIndex() {
    re=$1
    catdir=$2
    objectName=$3
    indexdir=$4

    build-astrometry-index -i $catdir/"$objectName"_Gaia_eDR3.fits -e1 \
                            -P $re \
                            -S phot_g_mean_mag \
                            -E -A RA -D  DEC\
                            -o $indexdir/index_$re.fits;
}
export -f downloadIndex

solveField() {
    i=$1
    solve_field_L_Param=$2
    solve_field_H_Param=$3
    solve_field_u_Param=$4
    ra_gal=$5
    dec_gal=$6
    confFile=$7
    astroimadir=$8

    base=$( basename $i)

    # The default sextractor parameter file is used.
    # I tried to use the one of the config directory (which is used in other steps), but even using the default one, it fails
    # Maybe a bug? I have not managed to make it work
    solve-field $i --no-plots \
    -L $solve_field_L_Param -H $solve_field_H_Param -u $solve_field_u_Param \
    --ra=$ra_gal --dec=$dec_gal --radius=3. \
    --overwrite --extension 1 --config $confFile/astrometry_$objectName.cfg --no-verify -E 1 -c 0.01 \
    --odds-to-solve 1e9 \
    --use-source-extractor --source-extractor-path=/usr/bin/source-extractor \
    -Unone --temp-axy -Snone -Mnone -Rnone -Bnone -N$astroimadir/$base ;
}
export -f solveField

runSextractorOnImage() {
    a=$1
    sexcfg=$2
    sexparam=$3
    sexconv=$4
    astroimadir=$5
    sexdir=$6
    saturationThreshold=$7
    gain=$8 

    # Here I put the saturation threshold and the gain directly.
    # This is because it's likely that we end up forgetting about tuning the sextractor configuration file but we will be more careful with the configuration file of the reductions
    # These two values (saturation level and gain) are key for astrometrising correctly, they are used by scamp for identifying saturated sources and weighting the sources
    # I was, in fact, having frames bad astrometrised due to this parameters.
    i=$astroimadir/"$a".fits
    echo source-extractor $i -c $sexcfg -PARAMETERS_NAME $sexparam -FILTER_NAME $sexconv -CATALOG_NAME $sexdir/$a.cat -SATUR_LEVEL=$saturationThreshold -GAIN=$gain
    source-extractor $i -c $sexcfg -PARAMETERS_NAME $sexparam -FILTER_NAME $sexconv -CATALOG_NAME $sexdir/$a.cat -SATUR_LEVEL=$saturationThreshold -GAIN=$gain
}
export -f runSextractorOnImage

checkIfSameBricksHaveBeenComputed() {
    currentBrick=$1
    bricksToLookFor=$2
    frameBrickCorrespondenceFile=$3

    # I build an array with the bricks to look for because the function receives an string
    bricksToLookForArray=()
    for i in $bricksToLookFor; do
        bricksToLookForArray+=("$i")
    done


    while read -r line; do
        # I read the frame number and its associated bricks
        imageNumber=$(echo "$line" | awk -F '[_.]' '{print $2}')
        string_list=$(echo "$line" | sed -E "s/.*\[(.*)\]/\1/" | tr -d "'")
        IFS=', ' read -r -a readBricksArray <<< "$string_list"

        # I sort them because we don't care about the order
        readBricksArray=($(printf '%s\n' "${readBricksArray[@]}" | sort))
        bricksToLookForArray=($(printf '%s\n' "${bricksToLookForArray[@]}" | sort))

        # Looking for coincidences
        if [[ ${#readBricksArray[@]} -eq 4 && ${#bricksToLookForArray[@]} -eq 4 ]]; then

            all_match=true
            for i in "${!bricksToLookForArray[@]}"; do
                if [[ "${bricksToLookForArray[$i]}" != "${readBricksArray[$i]}" ]]; then
                    all_match=false
                    break
                fi      
            done

            if [[ "$all_match" = true  ]]; then
                echo $imageNumber
                exit
            fi
        fi
    done < $frameBrickCorrespondenceFile
    echo 0
}
export -f checkIfSameBricksHaveBeenComputed


selectStarsAndSelectionRangeDecalsForFrame() {
    a=$1
    framesForCalibrationDir=$2
    mosaicDir=$3
    decalsImagesDir=$4
    frameBrickCorrespondenceFile=$5
    selectedDecalsStarsDir=$6
    rangeUsedDecalsDir=$7
    filter=$8
    downSampleDecals=$9
    diagnosis_and_badFilesDir=${10}
    brickCombinationsDir=${11}
    tmpFolderParent=${12}

    base="entirecamera_"$a.fits
    bricks=$( getBricksWhichCorrespondToFrame $framesForCalibrationDir/$base $frameBrickCorrespondenceFile )

    # Why do we need each process to go into its own folder? 
    # Even if all the temporary files have a unique name (whatever_$a...), swarpgenerates tmp files in the working directory
    # So, if two different sets of bricks are being processed at the same time and they have some common brick, it might fail
    # (two process with temporary files with the same name in the same directory). That's why every process go into its own folder
    tmpFolder=$tmpFolderParent/$a
    if ! [ -d $tmpFolder ]; then mkdir $tmpFolder; fi   
    cd $tmpFolder

    images=()
    for currentBrick in $bricks; do # I have to go through all the bricks for each frame
        # Remark that the ' ' at the end of the strings is needed. Otherwise when calling $images in the swarpthe names are not separated
        if [ "$filter" = "lum" ]; then
            images+=$downSampleDecals/"originalGrid_decal_image_"$currentBrick"_g+r_div2.fits "
        elif [ "$filter" = "i" ]; then
            images+=$downSampleDecals/"originalGrid_decal_image_"$currentBrick"_r+z_div2.fits "
        else
            images+=$downSampleDecals/"originalGrid_decal_image_"$currentBrick"_$filter.fits "
        fi
    done

    # Combining the downsampled decals image in one
    swarp $images -IMAGEOUT_NAME $tmpFolder/swarp1_$a.fits -WEIGHTOUT_NAME $tmpFolder/swarp_w1_$a.fits  2>/dev/null
    astarithmetic $tmpFolder/swarp_w1_$a.fits -h0 set-i i i 0 lt nan where -o$tmpFolder/temp1_$a.fits
    astarithmetic $tmpFolder/swarp1_$a.fits -h0 $tmpFolder/temp1_$a.fits -h1 0 eq nan where -o$brickCombinationsDir/combinedBricks_"$(basename $a)".fits
    imageToFindStarsAndPointLikeParameters=$brickCombinationsDir/combinedBricks_"$(basename $a)".fits

    # The following calls to astnoisechisel differ in the --tilesize parameter. The one with 10x10 is for working at reduced resolution (TST rebinned by 3 resolution in my case)
    # and the bigger for working with decals at original resolution. 
    # catalogueName=$(generateCatalogueFromImage_noisechisel $imageToFindStarsAndPointLikeParameters $tmpFolder $a 10)
    # catalogueName=$(generateCatalogueFromImage_noisechisel $imageToFindStarsAndPointLikeParameters $tmpFolder $a 50)
    catalogueName=$(generateCatalogueFromImage_sextractor $imageToFindStarsAndPointLikeParameters $tmpFolder $a)

    astmatch $catalogueName --hdu=1 $BDIR/catalogs/"$objectName"_Gaia_eDR3.fits --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=$toleranceForMatching/3600 --outcols=aX,aY,aRA,aDEC,aHALF_MAX_RADIUS,aMAGNITUDE -o $tmpFolder/match_decals_gaia_$a.txt 1>/dev/null

    # The intermediate step with awk is because I have come across an Inf value which make the std calculus fail
    # Maybe there is some beautiful way of ignoring it in gnuastro. I didn't find int, I just clean de inf fields.
    s=$(asttable $tmpFolder/match_decals_gaia_$a.txt -h1 -c5 --noblank=MAGNITUDE   | awk '{for(i=1;i<=NF;i++) if($i!="inf") print $i}' | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-median)
    std=$(asttable $tmpFolder/match_decals_gaia_$a.txt -h1 -c5 --noblank=MAGNITUDE | awk '{for(i=1;i<=NF;i++) if($i!="inf") print $i}' | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-std)
    minr=$(astarithmetic $s $sigmaForPLRegion $std x - -q)
    maxr=$(astarithmetic $s $sigmaForPLRegion $std x + -q)

    # Here call python script for generate the half-max-radius vs magnitudes
    halfMaxRadVsMagPlots_decalsDir=$diagnosis_and_badFilesDir/halfMaxRadVsMagPlots_decals
    if ! [ -d $halfMaxRadVsMagPlots_decalsDir ]; then mkdir $halfMaxRadVsMagPlots_decalsDir; fi
    outputPlotName=$halfMaxRadVsMagPlots_decalsDir/halfMaxRadVsMag_$a.png

    # These values are adequate for DECaLS range
    plotXLowerLimit=1
    plotXHigherLimit=15
    plotYLowerLimit=14
    plotYHigherLimit=26

    python3 $pythonScriptsPath/diagnosis_halfMaxRadVsMag.py $catalogueName $tmpFolder/match_decals_gaia_$a.txt $s $minr $maxr $outputPlotName \
            $plotXLowerLimit $plotXHigherLimit $plotYLowerLimit $plotYHigherLimit

    echo $s $std $minr $maxr > $rangeUsedDecalsDir/selected_rangeForFrame_"$a".txt
    asttable  $catalogueName --range=HALF_MAX_RADIUS,$minr,$maxr -o $selectedDecalsStarsDir/selected_decalsStarsForFrame_"$a".txt
    rm -rf $tmpFolder
}
export -f selectStarsAndSelectionRangeDecalsForFrame


selectStarsAndSelectionRangeDecals() {
    framesForCalibrationDir=$1
    mosaicDir=$2
    decalsImagesDir=$3
    frameBrickCorrespondenceFile=$4
    selectedDecalsStarsDir=$5
    rangeUsedDecalsDir=$6
    filter=$7
    downSampleDecals=$8
    diagnosis_and_badFilesDir=$9

    tmpFolder="$mosaicDir/tmpFilesForPhotometricCalibration"
    selectDecalsStarsDone=$selectedDecalsStarsDir/automaticSelection_done.txt
    brickCombinationsDir=$mosaicDir/combinedBricksForImages # I save the combination of the bricks for calibrating each image because I will need it in future steps of the calibration

    if ! [ -d $rangeUsedDecalsDir ]; then mkdir $rangeUsedDecalsDir; fi
    if ! [ -d $brickCombinationsDir ]; then mkdir $brickCombinationsDir; fi
    if ! [ -d $selectedDecalsStarsDir ]; then mkdir $selectedDecalsStarsDir; fi
    if ! [ -d $tmpFolder ]; then mkdir $tmpFolder; fi

    if [ -f $selectDecalsStarsDone ]; then
            echo -e "\n\tDecals bricks and stars for doing the photometric calibration are already selected for each frame\n"
    else
        # A lot of frames will have the same set of bricks becase they will be in the same sky region (same pointing)
        # The idea here is to take all the different set of bricks and parallelise its computation
        # Then loop through all the frames and copy the result (of that set of bricks) already calculated 
        # This is done this way because if I parallelise directly I will compute multiple times the same set of bricks
        declare -A unique_sets
        framesWithDifferentSets=()

        while IFS= read -r line; do
            filename=$(echo "$line" | awk '{print $1}' | awk -F'_' '{print $2}' | awk -F'.' '{print $1}')
            ids=$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p' | tr -d " '")
            sorted_ids=$(echo "$ids" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')

            if [[ -n "$sorted_ids" && -z "${unique_sets[$sorted_ids]}" ]]; then
                unique_sets[$sorted_ids]=$filename
                framesWithDifferentSets+=("$filename")
            fi
        done < $frameBrickCorrespondenceFile

        printf "%s\n" "${framesWithDifferentSets[@]}" | parallel -j "$num_cpus" selectStarsAndSelectionRangeDecalsForFrame {} $framesForCalibrationDir $mosaicDir $decalsImagesDir $frameBrickCorrespondenceFile $selectedDecalsStarsDir $rangeUsedDecalsDir $filter $downSampleDecals $diagnosis_and_badFilesDir $brickCombinationsDir $tmpFolder

        # Now we loop through all the frames. Every set should be already computed so it should go into the first clause of the if
        # I just add the else in case that some fails unexpectedly and the set of bricks of a frame are not already computed
        for a in $(seq 1 $totalNumberOfFrames); do
            base="entirecamera_"$a.fits
            bricks=$( getBricksWhichCorrespondToFrame $framesForCalibrationDir/$base $frameBrickCorrespondenceFile )
            
            if ! [[ -n "$bricks" ]]; then
              continue # Case when this frame has been rejected/lost
            fi
            imageToCopy=$( checkIfSameBricksHaveBeenComputed $a "$bricks" $frameBrickCorrespondenceFile )

            if [[ ("$imageToCopy" -gt 0) && ($imageToCopy != $a) ]]; then
                cp $selectedDecalsStarsDir/selected_decalsStarsForFrame_"$imageToCopy".txt $selectedDecalsStarsDir/selected_decalsStarsForFrame_"$a".txt 
                cp $rangeUsedDecalsDir/selected_rangeForFrame_"$imageToCopy".txt $rangeUsedDecalsDir/selected_rangeForFrame_"$a".txt
                cp $brickCombinationsDir/combinedBricks_"$(basename $imageToCopy)".fits $brickCombinationsDir/combinedBricks_"$a".fits
            elif [ $imageToCopy == $a ]; then
                : # A brick with itself (the firsts bricks with different sets of bricks, already computated. Simply pass)
            else 
                errorNumber=9
                echo Something went wrong in "selectStarsAndSelectionRangeDecals. Exiting with error number $errorNumber"
                exit $errorNumber
            fi
        done
        echo done > $selectDecalsStarsDone
    fi
    rmdir $tmpFolder
}
export -f selectStarsAndSelectionRangeDecals

prepareDecalsDataForPhotometricCalibration() {
    referenceImagesForMosaic=$1
    decalsImagesDir=$2
    filter=$3
    ra=$4
    dec=$5
    mosaicDir=$6
    selectedDecalsStarsDir=$7
    rangeUsedDecalsDir=$8
    dataPixelScale=$9
    diagnosis_and_badFilesDir=${10}
    sizeOfOurFieldDegrees=${11} 

    echo -e "\n ${GREEN} ---Preparing Decals data--- ${NOCOLOUR}"

    frameBrickCorrespondenceFile=$decalsImagesDir/frameBrickMap.txt
    ringFile=$BDIR/ring/ring.txt

    # This first steps donwloads the decals frames that are needed for calibrating each of our frames
    # The file "frameBrickCorrespondenceFile" will store the correspondence between our frames and decals bricks
    # This way we can easily access to this relation in orther to do the photometric calibration

    # If the images are donwloaded but the done.txt file is no present, the images won't be donwloaded again but
    # the step takes a while even if the images are already downloaded because we have to do a query to the database
    # in order to obtain the brickname and check if it is already downloaded or no
    if [ "$filter" = "lum" ]; then
        filters="g,r" # We download 'g' and 'r' because our images are taken with a luminance filter which response is a sort of g+r
        downloadDecalsData $referenceImagesForMosaic $mosaicDir $decalsImagesDir $frameBrickCorrespondenceFile $filters $ringFile

        # This step creates the images (g+r)/2. This is needed because we are using a luminance filter which is a sort of (g+r)
        # The division by 2 is because in AB system we work with Janskys, which are W Hz^-1 m^-2. So we have to give a flux per wavelenght
        # So, when we add two filters we have to take into account that we are increasing the wavelength rage. In our case, 'g' and 'r' have
        # practically the same wavelenght width, so dividing by 2 is enough
        addTwoFiltersAndDivideByTwo $decalsImagesDir "g" "r"

    elif [ "$filter" = "i" ]; then
        filters="r,z" # We download 'r' and 'z' because filter 'i' is not in all DECaLs
        downloadDecalsData $referenceImagesForMosaic $mosaicDir $decalsImagesDir $frameBrickCorrespondenceFile $filters $ringFile
        addTwoFiltersAndDivideByTwo $decalsImagesDir "r" "z"
    else 
        filters=$filter
        downloadDecalsData $referenceImagesForMosaic $mosaicDir $decalsImagesDir $frameBrickCorrespondenceFile $filters $ringFile
    fi


    # The photometric calibration is frame by frame, so we are not going to use the mosaic for calibration. But we build it anyway to retrieve in an easier way
    # the Gaia data of the whole field.
    buildDecalsMosaic $mosaicDir $decalsImagesDir $swarpcfg $ra $dec $filter $mosaicDir/downSampled $dataPixelScale $sizeOfOurFieldDegrees   

    echo -e "\n ${GREEN} ---Downloading GAIA catalogue for our field --- ${NOCOLOUR}"
    downloadGaiaCatalogueForField $mosaicDir

    
    # First of all remember that we need to do the photometric calibration frame by frame.
    # For each frame of the data, due to its large field, we have multiple (in our case 4 - defined in "downloadBricksForFrame.py") decals bricks
    echo -e "\n ${GREEN} --- Selecting stars and star selection range for Decals--- ${NOCOLOUR}"
    selectStarsAndSelectionRangeDecals $referenceImagesForMosaic $mosaicDir $decalsImagesDir $frameBrickCorrespondenceFile $selectedDecalsStarsDir $rangeUsedDecalsDir $filter $mosaicDir/downSampled $diagnosis_and_badFilesDir
}
export -f prepareDecalsDataForPhotometricCalibration

# Photometric calibration functions
# The function that is to be used (the 'public' function using OOP terminology)
# Is 'computeCalibrationFactors' and 'applyCalibrationFactors'
selectStarsAndRangeForCalibrateSingleFrame(){
    a=$1
    framesForCalibrationDir=$2
    mycatdir=$3
    tileSize=$4

    base="entirecamera_"$a.fits
    i=$framesForCalibrationDir/$base

    # outputCatalogue=$( generateCatalogueFromImage_noisechisel $i $mycatdir $a $tileSize  )
    outputCatalogue=$( generateCatalogueFromImage_sextractor $i $mycatdir $a $tileSize  )

    astmatch $outputCatalogue --hdu=1 $BDIR/catalogs/"$objectName"_Gaia_eDR3.fits --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=$toleranceForMatching/3600 --outcols=aX,aY,aRA,aDEC,aMAGNITUDE,aHALF_MAX_RADIUS -o$mycatdir/match_"$base"_my_gaia.txt

    s=$(asttable $mycatdir/match_"$base"_my_gaia.txt -h1 -c6 --noblank=MAGNITUDE | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-median)
    std=$(asttable $mycatdir/match_"$base"_my_gaia.txt -h1 -c6 --noblank=MAGNITUDE | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-std)
    minr=$(astarithmetic $s $sigmaForPLRegion $std x - -q)
    maxr=$(astarithmetic $s $sigmaForPLRegion $std x + -q)
    echo $s $std $minr $maxr > $mycatdir/range1_"$base".txt
    asttable $outputCatalogue    --range=HALF_MAX_RADIUS,$minr,$maxr -o $mycatdir/selected_"$base"_automatic.txt
}
export -f selectStarsAndRangeForCalibrateSingleFrame

selectStarsAndSelectionRangeOurData() {
    iteration=$1
    framesForCalibrationDir=$2
    mycatdir=$3
    tileSize=$4

    mycatdone=$mycatdir/done.txt
    if ! [ -d $mycatdir ]; then mkdir $mycatdir; fi
    if [ -f $mycatdone ]; then
            echo -e "\n\tSources for photometric calibration are already extracted for my image\n"
    else
        framesToUse=()
        for a in $(seq 1 $totalNumberOfFrames); do
            framesToUse+=("$a")
        done
        printf "%s\n" "${framesToUse[@]}" | parallel -j "$num_cpus" selectStarsAndRangeForCalibrateSingleFrame {} $framesForCalibrationDir $mycatdir $tileSize
        echo done > $mycatdone
    fi
}

matchDecalsAndOurData() {
    iteration=$1
    selectedDecalsStarsDir=$2
    mycatdir=$3
    matchdir2=$4

    matchdir2done=$matchdir2/done_automatic.txt
    if ! [ -d $matchdir2 ]; then mkdir $matchdir2; fi
    if [ -f $matchdir2done ]; then
        echo -e "\n\tMatch between decals (automatic) catalog and my (automatic) catalogs already done\n"
    else
        for a in $(seq 1 $totalNumberOfFrames); do
            base="entirecamera_$a.fits"
            out=$matchdir2/match-decals-"$base".cat

            tmpCatalogue=$matchdir2/match-$base-tmp.cat
            out_auto=$matchdir2/match-decals-"$base"_automatic.cat

            astmatch $selectedDecalsStarsDir/selected_decalsStarsForFrame_"$a".txt --hdu=1 $mycatdir/selected_"$base"_automatic.txt --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC \
                            --aperture=$toleranceForMatching/3600 --outcols=bX,bY,aX,aY,aRA,aDEC,bRA,bDEC,aMAGNITUDE,aHALF_MAX_RADIUS,bMAGNITUDE,bHALF_MAX_RADIUS -o$tmpCatalogue

            asttable $tmpCatalogue --output=$out_auto --colmetadata=1,X_INPUT_DATA,px,"X coordinate in data to reduce" \
                                    --colmetadata=2,Y_INPUT_DATA,px,"Y coordinate in data to reduce" \
                                    --colmetadata=3,X_CALIBRATION_DATA,px,"X coordinate in calibration data (DECaLS)" \
                                    --colmetadata=4,Y_CALIBRATION_DATA,px,"Y coordinate in calibration data (DECaLS)" \
                                    --colmetadata=5,RA_CALIBRATION_DATA,deg,"Right ascension in DECaLS" \
                                    --colmetadata=6,DEC_CALIBRATION_DATA,none,"Declination in DECaLS" \
                                    --colmetadata=7,RA_INPUT_DATA,deg,"Right ascension in data to reduce" \
                                    --colmetadata=8,DEC_INPUT_DATA,none,"Declination in data to reduce" \
                                    --colmetadata=9,MAGNITUDE,none,"Magnitude in calibration data" \
                                    --colmetadata=10,HALF-MAX-RADIUS,none,"Half-max-radius in calibration data" \
                                    --colmetadata=11,MAGNITUDE,none,"Magnitude in data to reduce" \
                                    --colmetadata=12,HALF-MAX-RADIUS,none,"Half-max-radius in data to reduce"                             
                                    
            rm $tmpCatalogue
        done
        echo done > $matchdir2done
    fi
}
export -f matchDecalsAndOurData

buildDecalsCatalogueOfMatchedSourcesForFrame() {
    a=$1
    decalsdir=$2
    rangeUsedDecalsDir=$3
    matchdir2=$4
    mosaicDir=$5
    decalsImagesDir=$6
    numberOfFWHMToUse=$7


    # I have to take 2 the FWHM (half-max-rad)
    # It is already saved as mean value of the point-like sources
    r_decals_pix_=$(awk 'NR==1 {printf $1}' $rangeUsedDecalsDir/"selected_rangeForFrame_"$a".txt")
    r_decals_pix=$(astarithmetic $r_decals_pix_ $numberOfFWHMToUse. x -q )

    base="entirecamera_$a.fits"
    matchedCatalogue=$matchdir2/match-decals-"$base"_automatic.cat

    decalsCombinedBricks=$mosaicDir/combinedBricksForImages/combinedBricks_$a.fits

    # raColumnName=RA_CALIBRATION_DATA
    # decColumnName=DEC_CALIBRATION_DATA
    # photometryOnImage_noisechisel $a $decalsdir $matchedCatalogue $decalsCombinedBricks $r_decals_pix $decalsdir/decals_"$base".cat \
    #                             22.5 $raColumnName $decColumnName
    
    columnWithXCoordForDecalsPx=2 # These numbers come from how the catalogue of the matches stars is built. This is not very clear right now, should be improved
    columnWithYCoordForDecalsPx=3
    columnWithXCoordForDecalsWCS=4
    columnWithYCoordForDecalsWCS=5  
    photometryOnImage_photutils $a $decalsdir "$matchedCatalogue" "$decalsCombinedBricks" $r_decals_pix $decalsdir/decals_"$base".cat \
                22.5 $columnWithXCoordForDecalsPx $columnWithYCoordForDecalsPx $columnWithXCoordForDecalsWCS $columnWithYCoordForDecalsWCS
}
export -f buildDecalsCatalogueOfMatchedSourcesForFrame

buildDecalsCatalogueOfMatchedSources() {
    decalsdir=$1
    rangeUsedDecalsDir=$2
    matchdir2=$3
    mosaicDir=$4
    decalsImagesDir=$5
    numberOfFWHMToUse=$6
    iteration=$7

    # We just compute it for the first iteration since the aperture photometry in decals does not change from iterations
    # Maybe this should be included in the "prepareDecalsDataForCalibration", but it wasn't initially there so here it is
    if [ "$iteration" -eq 1 ]; then
        decalsdone=$decalsdir/done.txt
        if ! [ -d $decalsdir ]; then mkdir $decalsdir; fi
        if [ -f $decalsdone ]; then
            echo -e "\n\tDecals: catalogue for the calibration stars already built\n"
        else
            framesToUse=()
            for a in $(seq 1 $totalNumberOfFrames); do
                framesToUse+=("$a")
            done
            printf "%s\n" "${framesToUse[@]}" | parallel -j "$num_cpus" buildDecalsCatalogueOfMatchedSourcesForFrame {} $decalsdir $rangeUsedDecalsDir $matchdir2 $mosaicDir $decalsImagesDir $numberOfFWHMToUse
            echo done > $decalsdone
        fi
    else
        echo -e "Decals aperture catalogs already built from previous iterations"
        folderName=$( echo $decalsdir | cut -d'_' -f1 )
        cp -r "$folderName"_it1 $decalsdir

    fi
}

buildOurCatalogueOfMatchedSourcesForFrame() {
    a=$1
    ourDatadir=$2
    framesForCalibrationDir=$3
    matchdir2=$4
    mycatdir=$5
    numberOfFWHMToUse=$6

    base="entirecamera_$a.fits"
    i=$framesForCalibrationDir/$base
    matchedCatalogue=$matchdir2/match-decals-"$base"_automatic.cat

    r_myData_pix_=$(awk 'NR==1 {printf $1}' $mycatdir/range1_"$base".txt)
    r_myData_pix=$(astarithmetic $r_myData_pix_ $numberOfFWHMToUse. x -q )

    # raColumnName=RA_INPUT_DATA
    # decColumnName=DEC_INPUT_DATA
    # photometryOnImage_noisechisel $a $ourDatadir $matchedCatalogue $i $r_myData_pix $ourDatadir/$base.cat 22.5 \
    #                                 $raColumnName $decColumnName

    columnWithXCoordForOutDataPx=0 # These numbers come from how the catalogue of the matches stars is built. This is not very clear right now, should be improved
    columnWithYCoordForOutDataPx=1
    columnWithXCoordForOutDataWCS=6
    columnWithYCoordForOutDataWCS=7
    photometryOnImage_photutils $a $ourDatadir $matchedCatalogue $i $r_myData_pix $ourDatadir/$base.cat 22.5 \
                                $columnWithXCoordForOutDataPx $columnWithYCoordForOutDataPx $columnWithXCoordForOutDataWCS $columnWithYCoordForOutDataWCS
}
export -f buildOurCatalogueOfMatchedSourcesForFrame

buildOurCatalogueOfMatchedSources() {
    ourDatadir=$1
    framesForCalibrationDir=$2
    matchdir2=$3
    mycatdir=$4
    numberOfFWHMToUse=$5

    ourDatadone=$ourDatadir/done.txt
    if ! [ -d $ourDatadir ]; then mkdir $ourDatadir; fi
    if [ -f $ourDatadone ]; then
        echo -e "\n\tAperture catalogs in our data done\n"
    else
        framesToUse=()
        for a in $(seq 1 $totalNumberOfFrames); do
            framesToUse+=("$a")
        done
        printf "%s\n" "${framesToUse[@]}" | parallel -j "$num_cpus" buildOurCatalogueOfMatchedSourcesForFrame {} $ourDatadir $framesForCalibrationDir $matchdir2 $mycatdir $numberOfFWHMToUse
        echo done > $ourDatadone
    fi
}

matchCalibrationStarsCatalogues() {
    matchdir2=$1
    ourDatadir=$2
    decalsdir=$3
    matchdir2done=$matchdir2/done_aperture.txt

    if [ -f $matchdir2done ]; then
        echo -e "\n\tMatch between decals (aperture) catalog and our (aperture) catalogs done for extension $h\n"
    else
        for a in $(seq 1 $totalNumberOfFrames); do
            base="entirecamera_$a.fits"
            i=$ourDatadir/"$base".cat

            out_tmp=$matchdir2/"$objectName"_Decals_"$a"_tmp.cat
            out=$matchdir2/"$objectName"_Decals-"$filter"_"$a".cat

            astmatch $decalsdir/decals_"$base".cat --hdu=1 $i --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=$toleranceForMatching/3600 --outcols=aRA,aDEC,bRA,bDEC,aMAGNITUDE,aSUM,bMAGNITUDE,bSUM -o$out_tmp
            asttable $out_tmp --output=$out --colmetadata=1,RA,deg,"Right ascension DECaLs" \
                        --colmetadata=2,DEC,none,"Declination DECaLs" \
                        --colmetadata=3,RA,deg,"Right ascension data being reduced" \
                        --colmetadata=4,DEC,none,"Declination data being reduced" \
                        --colmetadata=5,MAGNITUDE_CALIBRATED,none,"Magnitude in DECaLS data" \
                        --colmetadata=6,SUM,none,"Sum in DECaLS" \
                        --colmetadata=7,MAGNITUDE_NONCALIBRATED,none,"Magnitude in data being reduced" \
                        --colmetadata=8,SUM,none,"Sum in in data being reduced" 
            rm $out_tmp
        done
        echo done > $matchdir2done
    fi
}

computeAndStoreFactors() {
    alphatruedir=$1
    matchdir2=$2
    brightLimit=$3
    faintLimit=$4

    alphatruedone=$alphatruedir/done.txt
    numberOfStarsUsedToCalibrateFile=$alphatruedir/numberOfStarsUsedForCalibrate.txt

    if ! [ -d $alphatruedir ]; then mkdir $alphatruedir; fi
    if [ -f $alphatruedone ]; then
        echo -e "\n\tTrustable alphas computed for extension $h\n"
    else
        for a in $(seq 1 $totalNumberOfFrames); do
            base="$a".txt
            f=$matchdir2/"$objectName"_Decals-"$filter"_"$a".cat

            alphatruet=$alphatruedir/"$objectName"_Decals-"$filter"_"$a".txt
            asttable $f -h1 --range=MAGNITUDE_CALIBRATED,$brightLimit,$faintLimit -o$alphatruet
            asttable $alphatruet -h1 -c1,2,3,'arith $6 $8 /' -o$alphatruedir/$base

            mean=$(asttable $alphatruedir/$base -c'ARITH_1' | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-median)
            std=$(asttable $alphatruedir/$base -c'ARITH_1' | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --sigclip-std)
            echo "$mean $std" > $alphatruedir/alpha_"$objectName"_Decals-"$filter"_"$a".txt
            count=$(asttable $alphatruedir/$base -c'ARITH_1' | aststatistics --sclipparams=$sigmaForStdSigclip,$iterationsForStdSigClip --number)
            echo "Frame number $a: $count" >> $numberOfStarsUsedToCalibrateFile
        done
        echo done > $alphatruedone
    fi
}

computeCalibrationFactors() {
    iteration=$1
    imagesForCalibration=$2
    selectedDecalsStarsDir=$3
    rangeUsedDecalsDir=$4
    mosaicDir=$5
    decalsImagesDir=$6
    alphatruedir=$7
    brightLimit=$8
    faintLimit=$9
    tileSize=${10}
    numberOfFWHMForPhotometry=${11}

    mycatdir=$BDIR/my-catalog-halfmaxradius_it$iteration

    echo -e "\n ${GREEN} ---Selecting stars and range for our data--- ${NOCOLOUR}"
    selectStarsAndSelectionRangeOurData $iteration $imagesForCalibration $mycatdir $tileSize

    matchdir2=$BDIR/match-decals-myData_it$iteration
    echo -e "\n ${GREEN} ---Matching our data and Decals--- ${NOCOLOUR}"
    matchDecalsAndOurData $iteration $selectedDecalsStarsDir $mycatdir $matchdir2 

    decalsdir=$BDIR/decals-aperture-catalog_it$iteration
    echo -e "\n ${GREEN} ---Building Decals catalogue for (matched) calibration stars--- ${NOCOLOUR}"
    buildDecalsCatalogueOfMatchedSources $decalsdir $rangeUsedDecalsDir $matchdir2 $mosaicDir $decalsImagesDir $numberOfFWHMForPhotometry $iteration

    ourDataCatalogueDir=$BDIR/ourData-catalogs-apertures_it$iteration
    echo -e "\n ${GREEN} ---Building our catalogue for calibration stars--- ${NOCOLOUR}"
    buildOurCatalogueOfMatchedSources $ourDataCatalogueDir $imagesForCalibration $matchdir2 $mycatdir $numberOfFWHMForPhotometry

    echo -e "\n ${GREEN} ---Matching calibration stars catalogues--- ${NOCOLOUR}"
    matchCalibrationStarsCatalogues $matchdir2 $ourDataCatalogueDir $decalsdir

    echo -e "\n ${GREEN} ---Computing calibration factors (alpha)--- ${NOCOLOUR}"
    computeAndStoreFactors $alphatruedir $matchdir2 $brightLimit $faintLimit
}
export -f computeCalibrationFactors

applyCalibrationFactorsToFrame() {
    a=$1
    imagesForCalibration=$2
    alphatruedir=$3
    photCorrDir=$4

    base=entirecamera_"$a".fits
    f=$imagesForCalibration/"entirecamera_$a.fits"
    alpha_cat=$alphatruedir/alpha_"$objectName"_Decals-"$filter"_"$a".txt
    alpha=$(awk 'NR=='1'{print $1}' $alpha_cat)
    echo astarithmetic $f -h1 $alpha x float32 -o $photCorrDir/$base
    astarithmetic $f -h1 $alpha x float32 -o $photCorrDir/$base
}
export -f applyCalibrationFactorsToFrame

applyCalibrationFactors() {
    imagesForCalibration=$1
    alphatruedir=$2
    photCorrDir=$3

    muldone=$photCorrDir/done.txt
    if ! [ -d $photCorrDir ]; then mkdir $photCorrDir; fi
    if [ -f $muldone ]; then
            echo -e "\n\tMultiplication for alpha in the pointings (huge grid) is done for extension $h\n"
    else
        framesToApplyFactor=()
        for a in $(seq 1 $totalNumberOfFrames); do
            framesToApplyFactor+=("$a")
        done
        printf "%s\n" "${framesToApplyFactor[@]}" | parallel -j "$num_cpus" applyCalibrationFactorsToFrame {} $imagesForCalibration $alphatruedir $photCorrDir
        echo done > $muldone
    fi
}
export -f applyCalibrationFactors

# Compute the weights o the frames based on the std of the background
# In order to perform a weighted mean
computeWeightForFrame() {
    a=$1
    wdir=$2
    wonlydir=$3
    photCorrDir=$4
    noiseskydir=$5 
    iteration=$6
    minRmsFileName=$7

    h=0

    base=entirecamera_"$a".fits
    basetmp=entirecamera_"$a"_tmp.fits

    f=$photCorrDir/$base
    rms_min=$(awk 'NR=='1'{print $1}' $BDIR/$minRmsFileName)
    rms_f=$(awk 'NR=='1'{print $3}' $noiseskydir/entirecamera_$a.txt)

    weight=$(astarithmetic $rms_min $rms_f / --quiet)
    echo "$weight" > $wdir/"$objectName"_Decals-"$filter"_"$a"_ccd"$h".txt        #    saving into file

    # multiply each image for its weight
    wixi_im_tmp=$wdir/$basetmp                     # frame x weight
    w_im_tmp=$wonlydir/$basetmp                     # only weight
    wixi_im=$wdir/$base                     # frame x weight
    w_im=$wonlydir/$base                     # only weight

    astarithmetic $f -h1 $weight x --type=float32 -o$wixi_im_tmp 
    astarithmetic $wixi_im_tmp -h1 $f -h1 / --type=float32 -o$w_im_tmp
    astarithmetic $wixi_im_tmp float32 -g1 -o$wixi_im
    astarithmetic $w_im_tmp float32 -g1 -o$w_im
    rm -f $wixi_im_tmp
    rm -f $w_im_tmp


}
export -f computeWeightForFrame

computeWeights() {
    wdir=$1
    wdone=$2
    wonlydir=$3
    wonlydone=$4
    photCorrDir=$5
    noiseskydir=$6 
    iteration=$7
    minRmsFileName=$8

    if [ -f $wdone ]; then
        echo -e "\n\tWeights computation done for extension $h\n"
    else
        framesToComputeWeight=()
        for a in $(seq 1 $totalNumberOfFrames); do
            framesToComputeWeight+=("$a")
        done
        printf "%s\n" "${framesToComputeWeight[@]}" | parallel -j "$num_cpus" computeWeightForFrame {} $wdir $wonlydir $photCorrDir $noiseskydir $iteration $minRmsFileName
        echo done > $wdone
        echo done > $wonlydone
    fi
}

# Outliers functions
buildUpperAndLowerLimitsForOutliers() {
    clippingdir=$1
    clippingdone=$2
    wdir=$3
    sigmaForStdSigclip=$4


    if ! [ -d $clippingdir ]; then mkdir $clippingdir; fi
    if [ -f $clippingdone ]; then
            echo -e "\n\tUpper and lower limits for building the masked of the weighted images already computed\n"
    else
            # Compute clipped median and std
            med_im=$clippingdir/median_image.fits
            std_im=$clippingdir/std_image.fits

            astarithmetic $(ls -v $wdir/*.fits) $(ls $wdir/*.fits | wc -l) $sigmaForStdSigclip 0.2 sigclip-median -g1 -o$med_im
            astarithmetic $(ls -v $wdir/*.fits) $(ls $wdir/*.fits | wc -l) $sigmaForStdSigclip 0.2 sigclip-std -g1 -o$std_im
            # Compute "borders" images
            up_lim=$clippingdir/upperlim.fits
            lo_lim=$clippingdir/lowerlim.fits
            astarithmetic 4. $std_im x -o thresh.fits
            astarithmetic $med_im thresh.fits + -g1 float32 -o $up_lim
            astarithmetic $med_im thresh.fits - -g1 float32 -o $lo_lim

            #rm -f $med_im $std_im
            rm thresh.fits
            echo done > $clippingdone
    fi
}

removeOutliersFromFrame(){
    a=$1
    mowdir=$2
    moonwdir=$3
    clippingdir=$4
    wdir=$5
    wonlydir=$6

    base=entirecamera_"$a".fits
    tmp_ab=$mowdir/"$objectName"_Decals-"$filter"_"$a"_ccd"$h"_maskabove.fits
    wom=$mowdir/$base

    astarithmetic $wdir/$base -h1 set-i i i $clippingdir/upperlim.fits -h1 gt nan where float32 -q -o $tmp_ab
    astarithmetic $tmp_ab -h1 set-i i i $clippingdir/lowerlim.fits -h1 lt nan where float32 -q -o$wom
    # save the new mask
    mask=$mowdir/"$objectName"_Decals-"$filter"_"$a"_ccd"$h"_mask.fits
    astarithmetic $wom -h1 isblank float32 -o $mask
    # mask the onlyweight image
    owom=$moonwdir/$base
    astarithmetic $wonlydir/$base $mask -g1 1 eq nan where -q float32    -o $owom

    # Remove temporary files
    rm -f $tmp_ab
    rm -f $mask
}
export -f removeOutliersFromFrame

removeOutliersFromWeightedFrames () {
  mowdone=$1
  totalNumberOfFrames=$2
  mowdir=$3
  moonwdir=$4
  clippingdir=$5
  wdir=$6
  wonlydir=$7

  if [ -f $mowdone ]; then
      echo -e "\n\tOutliers of the weighted images already masked\n"
  else
      framesToRemoveOutliers=()
      for a in $(seq 1 $totalNumberOfFrames); do
          framesToRemoveOutliers+=("$a")
      done
      printf "%s\n" "${framesToRemoveOutliers[@]}" | parallel -j "$num_cpus" removeOutliersFromFrame {} $mowdir $moonwdir $clippingdir $wdir $wonlydir
      echo done > $mowdone 
  fi
}
export -f removeOutliersFromWeightedFrames

# Functions for applying the mask of the coadd for a second iteration
cropAndApplyMaskPerFrame() {
    a=$1
    dirOfFramesToMask=$2
    dirOfFramesMasked=$3
    wholeMask=$4
    dirOfFramesFullGrid=$5


    frameToMask=$dirOfFramesToMask/entirecamera_$a.fits
    frameToObtainCropRegion=$dirOfFramesFullGrid/entirecamera_$a.fits
    tmpMaskFile=$dirOfFramesMasked/"maskFor"$a.fits

    # Parameters for identifing our frame in the full grid
    frameCentre=$( getCentralCoordinate $frameToMask )
    centralRa=$(echo "$frameCentre" | awk '{print $1}')
    centralDec=$(echo "$frameCentre" | awk '{print $2}')

    regionOfDataInFullGrid=$(python3 $pythonScriptsPath/getRegionToCrop.py $frameToObtainCropRegion 1)
    read row_min row_max col_min col_max <<< "$regionOfDataInFullGrid"
    astcrop $wholeMask --polygon=$col_min,$row_min:$col_max,$row_min:$col_max,$row_max:$col_min,$row_max --mode=img  -o $tmpMaskFile --quiet
    astarithmetic $frameToMask -h1 $tmpMaskFile -h1 1 eq nan where float32 -o $dirOfFramesMasked/entirecamera_$a.fits -q
    rm $tmpMaskFile
}
export -f cropAndApplyMaskPerFrame

# maskPointings receives the directory with the frames in the full grid because we need it in order to know the region of the full grid
# in which the specific frame is located. That is obtained by using getRegionToCrop.py frame
maskPointings() {
    entiredir_smallGrid=$1
    smallPointings_maskedDir=$2
    maskedPointingsDone=$3
    maskName=$4
    dirOfFramesFullGrid=$5

    if ! [ -d $smallPointings_maskedDir ]; then mkdir $smallPointings_maskedDir; fi
    if [ -f $maskedPointingsDone ]; then
            echo -e "\nThe masks for the pointings have been already applied\n"
    else
        framesToMask=()
        for a in $(seq 1 $totalNumberOfFrames); do
            framesToMask+=("$a")
        done
        printf "%s\n" "${framesToMask[@]}" | parallel -j "$num_cpus" cropAndApplyMaskPerFrame {} $entiredir_smallGrid $smallPointings_maskedDir $maskName $dirOfFramesFullGrid
        echo done > $maskedPointingsDone 
    fi
}
export -f maskPointings

produceAstrometryCheckPlot() {
    myCatalogue=$1
    referenceCatalogue=$2
    pythonScriptsPath=$3
    output=$4
    pixelScale=$5

    astrometryTmpDir="./astrometryDiagnosisTmp"
    if ! [ -d $astrometryTmpDir ]; then mkdir $astrometryTmpDir; fi

    for i in $myCatalogue/match*.txt; do
        myFrame=$i
        frameNumber=$(echo "$i" | awk -F '[/]' '{print $(NF)}' | awk -F '[.]' '{print $(1)}' | awk -F '[_]' '{print $(NF)}')
        referenceFrame=$referenceCatalogue/*_$frameNumber.*
        astmatch $referenceFrame --hdu=1 $myFrame --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=1.7/3600 --outcols=aRA,aDEC,bRA,bDEC -o./$astrometryTmpDir/$frameNumber.cat
       done

    python3 $pythonScriptsPath/diagnosis_deltaRAdeltaDEC.py $astrometryTmpDir $output $pixelScale
    rm -r $astrometryTmpDir
}
export -f produceAstrometryCheckPlot

produceCalibrationCheckPlot() {
    myCatalogue_nonCalibrated=$1
    myFrames_calibrated=$2
    aperturesForMyData_dir=$3
    referenceCatalogueDir=$4
    pythonScriptsPath=$5
    output=$6
    calibrationBrighLimit=$7
    calibrationFaintLimit=$8
    numberOfFWHMToUse=$9
    outputDir=${10}

    tmpDir="./calibrationDiagnosisTmp"
    if ! [ -d $tmpDir ]; then mkdir $tmpDir; fi

    for i in $myCatalogue_nonCalibrated/*.cat; do
        myFrame=$i
        frameNumber=$(echo "$i" | awk -F '[/]' '{print $(NF)}' | awk -F '[.]' '{print $(1)}' | awk -F '[_]' '{print $(NF)}')
        referenceCatalogue=$referenceCatalogueDir/*_$frameNumber.*

        myCalibratedFrame=$myFrames_calibrated/entirecamera_$frameNumber.fits
        myNonCalibratedCatalogue=$myCatalogue_nonCalibrated/entirecamera_$frameNumber.fits*
        fileWithMyApertureData=$aperturesForMyData_dir/range1_entirecamera_$frameNumber*

        r_myData_pix_=$(awk 'NR==1 {printf $1}' $fileWithMyApertureData)
        r_myData_pix=$(astarithmetic $r_myData_pix_ $numberOfFWHMToUse. x -q )

        # raColumnName=RA
        # decColumnName=DEC
        # photometryOnImage_noisechisel -1 $tmpDir $myNonCalibratedCatalogue $myCalibratedFrame $r_myData_pix $tmpDir/$frameNumber.cat 22.5 \
        #                                 $raColumnName $decColumnName


        columnWithXCoordForOutDataPx=1 # These numbers come from how the catalogue of the matches stars is built. This is not very clear right now, should be improved
        columnWithYCoordForOutDataPx=2
        columnWithXCoordForOutDataWCS=3
        columnWithYCoordForOutDataWCS=4
        photometryOnImage_photutils -1 $tmpDir $myNonCalibratedCatalogue $myCalibratedFrame $r_myData_pix $tmpDir/$frameNumber.cat 22.5 \
                                    $columnWithXCoordForOutDataPx $columnWithYCoordForOutDataPx $columnWithXCoordForOutDataWCS $columnWithYCoordForOutDataWCS

        astmatch $referenceCatalogue --hdu=1 $tmpDir/$frameNumber.cat --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=1/3600 --outcols=aMAGNITUDE,bMAGNITUDE -o$tmpDir/"$frameNumber"_matched.cat
        rm $tmpDir/$frameNumber.cat
  done

python3 $pythonScriptsPath/diagnosis_magVsDeltaMag.py $tmpDir $output $outputDir $calibrationBrighLimit $calibrationFaintLimit
rm -rf $tmpDir
}
export -f produceCalibrationCheckPlot

produceHalfMaxRadVsMagForSingleImage() {
    image=$1 
    outputDir=$2
    gaiaCat=$3
    toleranceForMatching=$4
    pythonScriptsPath=$5
    alternativeIdentifier=$6 # Applied when there is no number in the name
    tileSize=$7

    a=$( echo $image | grep -oP '\d+(?=\.fits)' )
    if ! [[ -n "$a" ]]; then
        a=$alternativeIdentifier
    fi

    # catalogueName=$(generateCatalogueFromImage_noisechisel $image $outputDir $a $tileSize)
    catalogueName=$(generateCatalogueFromImage_sextractor $image $outputDir $a)

    astmatch $catalogueName --hdu=1 $gaiaCat --hdu=1 --ccol1=RA,DEC --ccol2=RA,DEC --aperture=$toleranceForMatching/3600 --outcols=aX,aY,aRA,aDEC,aHALF_MAX_RADIUS,aMAGNITUDE -o $outputDir/match_decals_gaia_$a.txt 
    
    plotXLowerLimit=0.5
    plotXHigherLimit=15
    plotYLowerLimit=12
    plotYHigherLimit=22
    python3 $pythonScriptsPath/diagnosis_halfMaxRadVsMag.py $catalogueName $outputDir/match_decals_gaia_$a.txt -1 -1 -1 $outputDir/$a.png  \
        $plotXLowerLimit $plotXHigherLimit $plotYLowerLimit $plotYHigherLimit

    rm $catalogueName $outputDir/match_decals_gaia_$a.txt 
}
export -f produceHalfMaxRadVsMagForSingleImage


produceHalfMaxRadVsMagForOurData() {
    imagesDir=$1
    outputDir=$2
    gaiaCat=$3
    toleranceForMatching=$4
    pythonScriptsPath=$5
    num_cpus=$6
    tileSize=$7

    images=()
    for i in $imagesDir/*.fits; do
        images+=("$i")
    done
    # images=("/home/sguerra/Sculptor/build/photCorrSmallGrid-dir_it1/entirecamera_1.fits")
    printf "%s\n" "${images[@]}" | parallel --line-buffer -j "$num_cpus" produceHalfMaxRadVsMagForSingleImage {} $outputDir $gaiaCat $toleranceForMatching $pythonScriptsPath "-" $tileSize
}
export -f produceHalfMaxRadVsMagForOurData

buildCoadd() {
    coaddir=$1
    coaddName=$2
    mowdir=$3
    moonwdir=$4
    coaddone=$5


    if ! [ -d $coaddir ]; then mkdir $coaddir; fi
    if [ -f $coaddone ]; then
            echo -e "\n\tThe first weighted (based upon std) mean of the images already done\n"
    else
            astarithmetic $(ls -v $mowdir/*.fits) $(ls $mowdir/*.fits | wc -l) sum -g1 -o$coaddir/"$k"_wx.fits
            astarithmetic $(ls -v $moonwdir/*.fits ) $(ls $moonwdir/*.fits | wc -l) sum -g1 -o$coaddir/"$k"_w.fits
            astarithmetic $coaddir/"$k"_wx.fits -h1 $coaddir/"$k"_w.fits -h1 / -o$coaddName
            echo done > $coaddone
    fi
}

subtractCoaddToFrames() {
    dirWithFrames=$1
    coadd=$2
    destinationDir=$3

    for i in $dirWithFrames/*.fits; do
        astarithmetic $i $coadd - -o$destinationDir/$( basename $i ) -g1
    done
}
export -f subtractCoaddToFrames

changeNonNansOfFrameToOnes() {
  a=$1
  framesDir=$2
  outputDir=$3

  frame=$framesDir/entirecamera_$a.fits
  output=$outputDir/exposure_tmp_$a.fits

  astarithmetic $frame $frame 0 gt 1 where --output=$output -g1
}
export -f changeNonNansOfFrameToOnes

computeExposureMap() {
    framesDir=$1
    exposureMapDir=$2
    exposureMapDone=$3

    if ! [ -d $exposuremapDir ]; then mkdir $exposuremapDir; fi
    if [ -f $exposuremapdone ]; then
        echo -e "\n\tThe exposure map is already done\n"
    else
      framesDir=$BDIR/pointings_fullGrid
      framesToProcess=()
      for a in $(seq 1 $totalNumberOfFrames); do
        framesToProcess+=("$a")
      done
      
      printf "%s\n" "${framesToProcess[@]}" | parallel -j "$num_cpus" changeNonNansOfFrameToOnes {} $framesDir $exposuremapDir
      astarithmetic $(ls -v $exposuremapDir/*.fits) $(ls $exposuremapDir/*.fits | wc -l) sum -g1 -o$coaddDir/exposureMap.fits
      rm -rf $exposuremapDir
      echo done > $exposuremapdone
    fi
}
export -f computeExposureMap






# ------------------------------------------------------------------------------------------------------
# Functions for generating the catalogue of an image
# For the moment these are in the calibration and when we need to make a half-max-radius vs magnitude plot

# In order to be used interchangeable, they have to return a catalogue with the following columns:
# 1.- X
# 2.- Y
# 3.- RA
# 4.- DEC
# 3.- Magnitude
# 4.- FWHM/2

generateCatalogueFromImage_noisechisel() { 
    image=$1
    outputDir=$2
    a=$3   
    tileSize=$4

    astmkprof --kernel=gaussian,1.5,3 --oversample=1 -o $outputDir/kernel_$a.fits 1>/dev/null
    astconvolve $image --kernel=$outputDir/kernel_$a.fits --domain=spatial --output=$outputDir/convolved_$a.fits 1>/dev/null
    astnoisechisel $image -h1 -o $outputDir/det_$a.fits --convolved=$outputDir/convolved_$a.fits --tilesize=$tileSize,$tileSize 1>/dev/null
    astsegment $outputDir/det_$a.fits -o $outputDir/seg_$a.fits --gthresh=-15 --objbordersn=0 1>/dev/null
    astmkcatalog $outputDir/seg_$a.fits --x --y --ra --dec --magnitude --half-max-radius --sum --clumpscat -o $outputDir/decals_$a.txt --zeropoint=22.5 1>/dev/null

    rm $outputDir/kernel_$a.fits $outputDir/convolved_$a.fits $outputDir/det_$a.fits $outputDir/seg_$a.fits  $outputDir/decals_"$a"_o.txt
    echo $outputDir/decals_"$a"_c.txt
}
export -f generateCatalogueFromImage_noisechisel


generateCatalogueFromImage_sextractor(){
    image=$1
    outputDir=$2
    a=$3   

    # I specify the configuration path here because in the photometric calibration the working directoy changes. This has to be changed and use the config path given in the pipeline
    cfgPath=$ROOTDIR/"$objectName"/config

    source-extractor $image -c $cfgPath/sextractor_detection.sex -CATALOG_NAME $outputDir/"$a"_tmp.cat -FILTER_NAME $cfgPath/default.conv -PARAMETERS_NAME $cfgPath/sextractor_detection.param  1>/dev/null 2>&1
    awk '{ $6 = $6 / 2; print }' $outputDir/"$a"_tmp.cat > $outputDir/"$a".cat # I divide because SExtractor gives the FWHM and the pipeline expects half

    # Headers to mimic the noisechisel format
    sed -i '1i# Column 6: HALF_MAX_RADIUS' $outputDir/$a.cat
    sed -i '1i# Column 5: MAGNITUDE      ' $outputDir/$a.cat
    sed -i '1i# Column 4: DEC            ' $outputDir/$a.cat
    sed -i '1i# Column 3: RA             ' $outputDir/$a.cat
    sed -i '1i# Column 2: Y              ' $outputDir/$a.cat
    sed -i '1i# Column 1: X              ' $outputDir/$a.cat

    rm $outputDir/"$a"_tmp.cat
    echo $outputDir/$a.cat
}
export -f generateCatalogueFromImage_sextractor



# ------------------------------------------------------------------------------------------------------
# Functions for performing photometry in an image
# They produce an output catalogue with the format
# 1.- ID
# 2.- X
# 3.- Y
# 4.- RA
# 5.- DEC
# 6.- MAGNITUDE
# 7.- SUM

photometryOnImage_noisechisel() {
    a=$1
    directoryToWork=$2
    matchedCatalogue=$3
    imageToUse=$4
    aperture_radius_px=$5
    outputCatalogue=$6
    zeropoint=$7
    raColumnName=$8
    decColumnName=$9


    echo "Image: " $imageToUse
    echo "Aperture: " $aperture_radius_px
    echo "names: " $raColumnName,$decColumnName
    echo $( asttable $matchedCatalogue -hSOURCE_ID -c$raColumnName,$decColumnName ) 

    asttable $matchedCatalogue -hSOURCE_ID -c$raColumnName,$decColumnName | awk '!/^#/{print NR, $1, $2, 5, '$aperture_radius_px', 0, 0, 1, NR, 1}' > $directoryToWork/apertures_decals_$a.txt
    astmkprof $directoryToWork/apertures_decals_$a.txt --background=$imageToUse --backhdu=1 \
            --clearcanvas --replace --type=int16 --mforflatpix \
            --mode=wcs --output=$directoryToWork/apertures_decals_$a.fits
    astmkcatalog $directoryToWork/apertures_decals_$a.fits -h1 --zeropoint=$zeropoint \
                    --valuesfile=$imageToUse --valueshdu=1 \
                    --ids --x --y --ra --dec --magnitude --sum \
                    --output=$outputCatalogue

    rm $directoryToWork/apertures_decals_$a.txt
    rm $directoryToWork/apertures_decals_$a.fits
}
export -f photometryOnImage_noisechisel

photometryOnImage_photutils() {
    a=$1
    directoryToWork=$2
    matchedCatalogue=$3
    imageToUse=$4
    aperture_radius_px=$5
    outputCatalogue=$6
    zeropoint=$7
    xColumnPx=$8
    yColumnPx=$9
    xColumnWCS=${10}
    yColumnWCS=${11}

    tmpCatalogName=$directoryToWork/tmp_"$a".cat
    python3 $pythonScriptsPath/photutilsPhotometry.py $matchedCatalogue $imageToUse $aperture_radius_px $tmpCatalogName $zeropoint $xColumnPx $yColumnPx $xColumnWCS $yColumnWCS

    asttable $tmpCatalogName -p4 --colmetadata=2,X,px,"X" \
                            --colmetadata=3,Y,px,"Y" \
                            --colmetadata=4,RA,deg,"Right ascension" \
                            --colmetadata=5,DEC,none,"Declination" \
                            --colmetadata=6,MAGNITUDE,none,"Magnitude" \
                            --colmetadata=7,SUM,none,"sum" \
                            --output=$outputCatalogue
    rm $tmpCatalogName
}
export -f photometryOnImage_photutils

limitingSurfaceBrightness() {
    image=$1
    mask=$2
    exposureMap=$3
    directoryOfImages=$4
    areaSB=$(printf "%.10f" "$5")
    fracExpMap=$(printf "%.10f" "$6")
    pixelScale=$(printf "%.10f" "$7")
    outFile=$8

    out_mask=$directoryOfImages/mask_det.fits
    astarithmetic $image -h1 $mask -hDETECTIONS 0 ne nan where -q --output=$out_mask

    out_maskexp=$directoryOfImages/mask_exp.fits
    expMax=$(aststatistics $exposureMap --maximum -q)
    expMax=$(printf "%.10f" "$expMax")
    exp_fr=$(echo "$expMax * $frExp" | bc -l)
    astarithmetic $out_mask $exposureMap -g1 $exp_fr lt nan where --output=$out_maskexp

    sigma=$(aststatistics $out_maskexp --std -q)
    sigma=$(printf "%.10f" "$sigma")

    sb_lim=$(echo "-2.5*l(3*$sigma/($areaSB/$pixelScale))/l(10)+22.5" | bc -l)
    echo "$sb_lim" > "$outFile"

    rm $out_mask $out_maskexp
}
export -f limitingSurfaceBrightness





