type file;

app runProcessPeaks (string paramsf, int RNr, file hkl)
{
 processPeaks paramsf RNr;
}


# Parameters to be modified #############

int startnr = toInt(arg("startnr","1"));
int endnr = toInt(arg("endnr","600"));
string parameterfilestem = arg("paramsfile","/clhome/TOMO1/PeaksAnalysisHemant/PeaksFittingCode/90_33ParamsFile1.txt");
string ringfile = arg("ringfile","RingInfo.txt");
string fstm = arg("fstm","PS.txt");

# End parameters ########################

file hkl <"hkls.csv">;

int rings[] = readData(ringfile);

foreach Ring in rings {
    string PFst1 = strcat(parameterfilestem,Ring);
    string parameterfilename = strcat(PFst1,"_",fstm);
    tracef("%s\n",parameterfilename);
    runProcessPeaks(parameterfilename,Ring,hkl);
}
