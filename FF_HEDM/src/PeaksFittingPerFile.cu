//
//  PeaksFittingPerFile.c
//  
//
//  Created by Hemant Sharma on 2014/07/04.
//
//
//  
// Only 8-connected is implemented for now.

#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <sys/stat.h>
#include <string.h>
#include <ctype.h>
#include <nlopt.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <errno.h>
#include <stdarg.h>
#include <fcntl.h>
#include "nldrmd.cuh"

#define deg2rad 0.0174532925199433
#define rad2deg 57.2957795130823
#define MAXNHKLS 5000
#define CalcNorm3(x,y,z) sqrt((x)*(x) + (y)*(y) + (z)*(z))
#define CalcNorm2(x,y) sqrt((x)*(x) + (y)*(y))
typedef uint16_t pixelvalue;

static inline
pixelvalue**
allocMatrixPX(int nrows, int ncols)
{
    pixelvalue** arr;
    int i;
    arr = malloc(nrows * sizeof(*arr));
    if (arr == NULL ) {
        return NULL;
    }
    for ( i = 0 ; i < nrows ; i++) {
        arr[i] = malloc(ncols * sizeof(*arr[i]));
        if (arr[i] == NULL ) {
            return NULL;
        }
    }
    return arr;
}

static inline
void
FreeMemMatrixPx(pixelvalue **mat,int nrows)
{
    int r;
    for ( r = 0 ; r < nrows ; r++) {
        free(mat[r]);
    }
    free(mat);
}

static inline 
double CalcEtaAngle(double y, double z){
	double alpha = rad2deg*acos(z/sqrt(y*y+z*z));
	if (y>0) alpha = -alpha;
	return alpha;
}

static inline
void YZ4mREta(int NrElements, double *R, double *Eta, double *Y, double *Z){
	int i;
	for (i=0;i<NrElements;i++){
		Y[i] = -R[i]*sin(Eta[i]*deg2rad);
		Z[i] = R[i]*cos(Eta[i]*deg2rad);
	}
}

static inline
int**
allocMatrixInt(int nrows, int ncols)
{
    int** arr;
    int i;
    arr = malloc(nrows * sizeof(*arr));
    if (arr == NULL ) {
        return NULL;
    }
    for ( i = 0 ; i < nrows ; i++) {
        arr[i] = malloc(ncols * sizeof(*arr[i]));
        if (arr[i] == NULL ) {
            return NULL;
        }
    }
    return arr;
}

static inline
void
FreeMemMatrixInt(int **mat,int nrows)
{
    int r;
    for ( r = 0 ; r < nrows ; r++) {
        free(mat[r]);
    }
    free(mat);
}

static inline
double**
allocMatrix(int nrows, int ncols)
{
    double** arr;
    int i;
    arr = malloc(nrows * sizeof(*arr));
    if (arr == NULL ) {
        return NULL;
    }
    for ( i = 0 ; i < nrows ; i++) {
        arr[i] = malloc(ncols * sizeof(*arr[i]));
        if (arr[i] == NULL ) {
            return NULL;
        }
    }
    return arr;
}

static inline
void
FreeMemMatrix(double **mat,int nrows)
{
    int r;
    for ( r = 0 ; r < nrows ; r++) {
        free(mat[r]);
    }
    free(mat);
}

static inline double sind(double x){return sin(deg2rad*x);}
static inline double cosd(double x){return cos(deg2rad*x);}
static inline double tand(double x){return tan(deg2rad*x);}
static inline double asind(double x){return rad2deg*(asin(x));}
static inline double acosd(double x){return rad2deg*(acos(x));}
static inline double atand(double x){return rad2deg*(atan(x));}

static inline int CalcNPlanes(int nrings, int RingNumbers, int CellStruct)
{
	int nplanes=0,i,RingNumber;
	if (CellStruct==2){
		for (i=0;i<nrings;i++){
			RingNumber = RingNumbers;
			if (RingNumber == 1)nplanes+=8;
			if (RingNumber == 2)nplanes+=6;
			if (RingNumber == 3)nplanes+=12;
			if (RingNumber == 4)nplanes+=24;
			if (RingNumber == 5)nplanes+=8;
			if (RingNumber == 6)nplanes+=6;
			if (RingNumber == 7)nplanes+=24;
			if (RingNumber == 8)nplanes+=24;
			if (RingNumber == 9)nplanes+=24;
			if (RingNumber == 10)nplanes+=8;
		}
	} else if (CellStruct==1){
		for (i=0;i<nrings;i++){
			RingNumber = RingNumbers;
			if (RingNumber == 1)nplanes+=12;
			if (RingNumber == 2)nplanes+=6;
			if (RingNumber == 3)nplanes+=24;
			if (RingNumber == 4)nplanes+=12;
			if (RingNumber == 5)nplanes+=24;
		}
	} else if (CellStruct==3){
		for (i=0;i<nrings;i++){
			RingNumber = RingNumbers;
			if (RingNumber == 1)nplanes+=6;
			if (RingNumber == 2)nplanes+=12;
			if (RingNumber == 3)nplanes+=8;
			if (RingNumber == 4)nplanes+=6;
			if (RingNumber == 5)nplanes+=24;
			if (RingNumber == 6)nplanes+=24;
			if (RingNumber == 7)nplanes+=12;
		}
	}
	return nplanes;
}

static inline void Transposer (double *x, int n, double *y)
{
	int i,j;
	for (i=0;i<n;i++){
		for (j=0;j<n;j++){
			y[(i*n)+j] = x[(j*n)+i];
		}
	}
}

const int dx[] = {+1,  0, -1,  0, +1, -1, +1, -1};
const int dy[] = { 0, +1,  0, -1, +1, +1, -1, -1};

static inline void DepthFirstSearch(int x, int y, int current_label, int NrPixels, int **BoolImage, int **ConnectedComponents,int **Positions, int *PositionTrackers)
{
	if (x < 0 || x == NrPixels) return;
	if (y < 0 || y == NrPixels) return;
	if ((ConnectedComponents[x][y]!=0)||(BoolImage[x][y]==0)) return;
	
	ConnectedComponents[x][y] = current_label;
	Positions[current_label][PositionTrackers[current_label]] = (x*NrPixels) + y;
	PositionTrackers[current_label] += 1;
	int direction;
	for (direction=0;direction<8;++direction){
		DepthFirstSearch(x + dx[direction], y + dy[direction], current_label, NrPixels, BoolImage, ConnectedComponents,Positions,PositionTrackers);
		
	}
}

static inline int FindConnectedComponents(int **BoolImage, int NrPixels, int **ConnectedComponents, int **Positions, int *PositionTrackers){
	int i,j;
	for (i=0;i<NrPixels;i++){
		for (j=0;j<NrPixels;j++){
			ConnectedComponents[i][j] = 0;
		}
	}
	int component = 0;
	for (i=0;i<NrPixels;++i) {
		for (j=0;j<NrPixels;++j) {
			if ((ConnectedComponents[i][j]==0) && (BoolImage[i][j] == 1)){
				DepthFirstSearch(i,j,++component,NrPixels,BoolImage,ConnectedComponents,Positions,PositionTrackers);
			}
		}
	}
	return component;
}

static inline unsigned FindRegionalMaxima(double *z,int **PixelPositions,
		int NrPixelsThisRegion,int **MaximaPositions,double *MaximaValues,
		int *IsSaturated, double IntSat)
{
	unsigned nPeaks = 0;
	int i,j,k,l;
	double zThis, zMatch;
	int xThis, yThis;
	int xNext, yNext;
	int isRegionalMax = 1;
	for (i=0;i<NrPixelsThisRegion;i++){
		isRegionalMax = 1;
		zThis = z[i];
		if (zThis > IntSat) {
			*IsSaturated = 1;
		} else {
			*IsSaturated = 0;
		}
		xThis = PixelPositions[i][0];
		yThis = PixelPositions[i][1];
		for (j=0;j<8;j++){
			xNext = xThis + dx[j];
			yNext = yThis + dy[j];
			for (k=0;k<NrPixelsThisRegion;k++){
				if (xNext == PixelPositions[k][0] && yNext == PixelPositions[k][1] && z[k] > (zThis)){
					isRegionalMax = 0;
				}
			}
		}
		if (isRegionalMax == 1){
			MaximaPositions[nPeaks][0] = xThis;
			MaximaPositions[nPeaks][1] = yThis;
			MaximaValues[nPeaks] = zThis;
			nPeaks++;
		}
	}
	if (nPeaks==0){
        MaximaPositions[nPeaks][0] = PixelPositions[NrPixelsThisRegion/2][0];	
        MaximaPositions[nPeaks][1] = PixelPositions[NrPixelsThisRegion/2][1];
        MaximaValues[nPeaks] = z[NrPixelsThisRegion/2];
        nPeaks=1;
	}
	return nPeaks;
}

struct func_data{
	int NrPixels;
	double *z;
	double *Rs;
	double *Etas;
};

static
double problem_function(
	unsigned n,
	const double *x,
	double *grad,
	void* f_data_trial)
{
	struct func_data *f_data = (struct func_data *) f_data_trial;
	int NrPixels = f_data->NrPixels;
	double *z,*Rs,*Etas;
	z = &(f_data->z[0]);
	Rs = &(f_data->Rs[0]);
	Etas = &(f_data->Etas[0]);
	int nPeaks, i,j,k;
	nPeaks = (n-1)/8;
	double BG = x[0];
	double IMAX[nPeaks], R[nPeaks], Eta[nPeaks], Mu[nPeaks], SigmaGR[nPeaks], SigmaLR[nPeaks], SigmaGEta[nPeaks],SigmaLEta[nPeaks];
	for (i=0;i<nPeaks;i++){
		IMAX[i] = x[(8*i)+1];
		R[i] = x[(8*i)+2];
		Eta[i] = x[(8*i)+3];
		Mu[i] = x[(8*i)+4];
		SigmaGR[i] = x[(8*i)+5];
		SigmaLR[i] = x[(8*i)+6];
		SigmaGEta[i] = x[(8*i)+7];
		SigmaLEta[i] = x[(8*i)+8];
	}
	double TotalDifferenceIntensity = 0, CalcIntensity, IntPeaks;
	double L, G;
	for (i=0;i<NrPixels;i++){
		IntPeaks = 0;
		for (j=0;j<nPeaks;j++){
			L = 1/(((((Rs[i]-R[j])*(Rs[i]-R[j]))/((SigmaLR[j])*(SigmaLR[j])))+1)*((((Etas[i]-Eta[j])*(Etas[i]-Eta[j]))/((SigmaLEta[j])*(SigmaLEta[j])))+1));
			G = exp(-(0.5*(((Rs[i]-R[j])*(Rs[i]-R[j]))/(SigmaGR[j]*SigmaGR[j])))-(0.5*(((Etas[i]-Eta[j])*(Etas[i]-Eta[j]))/(SigmaGEta[j]*SigmaGEta[j]))));
			IntPeaks += IMAX[j]*((Mu[j]*L) + ((1-Mu[j])*G));
		}
		CalcIntensity = BG + IntPeaks;
		TotalDifferenceIntensity += (CalcIntensity - z[i])*(CalcIntensity - z[i]);
	}
	return TotalDifferenceIntensity;
}

static inline void CalcIntegratedIntensity(int nPeaks,double *x,double *Rs,double *Etas,int NrPixelsThisRegion,double *IntegratedIntensity,int *NrOfPixels){
	double BG = x[0];
	int i,j;
	double IMAX[nPeaks], R[nPeaks], Eta[nPeaks], Mu[nPeaks], SigmaGR[nPeaks], SigmaLR[nPeaks], SigmaGEta[nPeaks],SigmaLEta[nPeaks];
	for (i=0;i<nPeaks;i++){
		IMAX[i] = x[(8*i)+1];
		R[i] = x[(8*i)+2];
		Eta[i] = x[(8*i)+3];
		Mu[i] = x[(8*i)+4];
		SigmaGR[i] = x[(8*i)+5];
		SigmaLR[i] = x[(8*i)+6];
		SigmaGEta[i] = x[(8*i)+7];
		SigmaLEta[i] = x[(8*i)+8];
	}
	double IntPeaks, L, G, BGToAdd;
	for (j=0;j<nPeaks;j++){
		NrOfPixels[j] = 0;
		IntegratedIntensity[j] = 0;
		for (i=0;i<NrPixelsThisRegion;i++){
			L = 1/(((((Rs[i]-R[j])*(Rs[i]-R[j]))/((SigmaLR[j])*(SigmaLR[j])))+1)*((((Etas[i]-Eta[j])*(Etas[i]-Eta[j]))/((SigmaLEta[j])*(SigmaLEta[j])))+1));
			G = exp(-(0.5*(((Rs[i]-R[j])*(Rs[i]-R[j]))/(SigmaGR[j]*SigmaGR[j])))-(0.5*(((Etas[i]-Eta[j])*(Etas[i]-Eta[j]))/(SigmaGEta[j]*SigmaGEta[j]))));
			IntPeaks = IMAX[j]*((Mu[j]*L) + ((1-Mu[j])*G));
			if (IntPeaks > BG){
				NrOfPixels[j] += 1;
				BGToAdd = BG;
			}else{
				BGToAdd = 0;
			}
			IntegratedIntensity[j] += (BGToAdd + IntPeaks);
		}
	}
}

void Fit2DPeaks(unsigned nPeaks, int NrPixelsThisRegion, double *z, int **UsefulPixels, double *MaximaValues,
				int **MaximaPositions, double *IntegratedIntensity, double *IMAX, double *YCEN, double *ZCEN, 
				double *RCens, double *EtaCens,double Ycen, double Zcen, double Thresh, int *NrPx,double *OtherInfo)
{
	unsigned n = 1 + (8*nPeaks);
	double x[n],xl[n],xu[n];
	x[0] = Thresh/2;
	xl[0] = 0;
	xu[0] = Thresh;
	int i;
	double *Rs, *Etas;
	Rs = malloc(NrPixelsThisRegion*2*sizeof(*Rs));
	Etas = malloc(NrPixelsThisRegion*2*sizeof(*Etas));
	for (i=0;i<NrPixelsThisRegion;i++){
		Rs[i] = CalcNorm2(UsefulPixels[i][0]-Ycen,UsefulPixels[i][1]-Zcen);
		Etas[i] = CalcEtaAngle(UsefulPixels[i][0]-Ycen,UsefulPixels[i][1]-Zcen);
	}
	double Width = sqrt(NrPixelsThisRegion/nPeaks);
	for (i=0;i<nPeaks;i++){
		x[(8*i)+1] = MaximaValues[i]; // Imax
		x[(8*i)+2] = CalcNorm2(MaximaPositions[i][0]-Ycen,MaximaPositions[i][1]-Zcen); //Radius
		x[(8*i)+3] = CalcEtaAngle(MaximaPositions[i][0]-Ycen,MaximaPositions[i][1]-Zcen); // Eta
		x[(8*i)+4] = 0.5; // Mu
		x[(8*i)+5] = Width; //SigmaGR
		x[(8*i)+6] = Width; //SigmaLR
		x[(8*i)+7] = atand(Width/x[(8*i)+2]); //SigmaGEta //0.5;
		x[(8*i)+8] = atand(Width/x[(8*i)+2]); //SigmaLEta //0.5;

		double dEta = rad2deg*atan(1/x[(8*i)+2]);
		xl[(8*i)+1] = MaximaValues[i]/2;
		xl[(8*i)+2] = x[(8*i)+2] - 1;
		xl[(8*i)+3] = x[(8*i)+3] - dEta;
		xl[(8*i)+4] = 0;
		xl[(8*i)+5] = 0.01;
		xl[(8*i)+6] = 0.01;
		xl[(8*i)+7] = 0.005;
		xl[(8*i)+8] = 0.005;

		xu[(8*i)+1] = MaximaValues[i]*2;
		xu[(8*i)+2] = x[(8*i)+2] + 1;
		xu[(8*i)+3] = x[(8*i)+3] + dEta;
		xu[(8*i)+4] = 1;
		xu[(8*i)+5] = 30;
		xu[(8*i)+6] = 30;
		xu[(8*i)+7] = 2;
		xu[(8*i)+8] = 2;
	}
	struct func_data f_data;
	f_data.NrPixels = NrPixelsThisRegion;
	f_data.Rs = &Rs[0];
	f_data.Etas = &Etas[0];
	f_data.z = &z[0];
	struct func_data *f_datat;
	f_datat = &f_data;
	void *trp = (struct func_data *)  f_datat;
	nlopt_opt opt;
	opt = nlopt_create(NLOPT_LN_NELDERMEAD, n);
	nlopt_set_lower_bounds(opt, xl);
	nlopt_set_upper_bounds(opt, xu);
	nlopt_set_maxtime(opt, 300);
	nlopt_set_min_objective(opt, problem_function, trp);
	double minf;
	nlopt_optimize(opt, x, &minf);
	nlopt_destroy(opt);
	for (i=0;i<nPeaks;i++){
		IMAX[i] = x[(8*i)+1];
		RCens[i] = x[(8*i)+2];
		EtaCens[i] = x[(8*i)+3];
		if (x[(8*i)+5] > x[(8*i)+6]){
			OtherInfo[2*i] = x[(8*i)+5];
		}else{
			OtherInfo[2*i] = x[(8*i)+6];
		}
		if (x[(8*i)+7] > x[(8*i)+8]){
			OtherInfo[2*i+1] = x[(8*i)+7];
		}else{
			OtherInfo[2*i+1] = x[(8*i)+8];
		}
	}
	YZ4mREta(nPeaks,RCens,EtaCens,YCEN,ZCEN);
	CalcIntegratedIntensity(nPeaks,x,Rs,Etas,NrPixelsThisRegion,IntegratedIntensity,NrPx);
	free(Rs);
	free(Etas);
}

static inline int CheckDirectoryCreation(char Folder[1024])
{
	int e;
    struct stat sb;
	char totOutDir[1024];
	sprintf(totOutDir,"%s/",Folder);
    e = stat(totOutDir,&sb);
    if (e!=0 && errno == ENOENT){
		printf("Output directory did not exist, creating %s\n",totOutDir);
		e = mkdir(totOutDir,S_IRWXU);
		if (e !=0) {printf("Could not make the directory. Exiting\n");return 0;}
	}
	return 1;
}

static inline void DoImageTransformations (int NrTransOpt, int TransOpt[10], pixelvalue *Image, int NrPixels)
{
	int i,j,k,l,m;
    pixelvalue **ImageTemp1, **ImageTemp2;
    ImageTemp1 = allocMatrixPX(NrPixels,NrPixels);
    ImageTemp2 = allocMatrixPX(NrPixels,NrPixels);
	for (k=0;k<NrPixels;k++) for (l=0;l<NrPixels;l++) ImageTemp1[k][l] = Image[(NrPixels*k)+l];
	for (k=0;k<NrTransOpt;k++) {
		if (TransOpt[k] == 1){
			for (l=0;l<NrPixels;l++) for (m=0;m<NrPixels;m++) ImageTemp2[l][m] = ImageTemp1[l][NrPixels-m-1]; //Inverting Y.
		} else if (TransOpt[k] == 2){
			for (l=0;l<NrPixels;l++) for (m=0;m<NrPixels;m++) ImageTemp2[l][m] = ImageTemp1[NrPixels-l-1][m]; //Inverting Z.
		} else if (TransOpt[k] == 3){
			for (l=0;l<NrPixels;l++) for (m=0;m<NrPixels;m++) ImageTemp2[l][m] = ImageTemp1[m][l];
		} else if (TransOpt[k] == 0){
			for (l=0;l<NrPixels;l++) for (m=0;m<NrPixels;m++) ImageTemp2[l][m] = ImageTemp1[l][m];
		}
		for (l=0;l<NrPixels;l++) for (m=0;m<NrPixels;m++) ImageTemp1[l][m] = ImageTemp2[l][m];
	}
	for (k=0;k<NrPixels;k++) for (l=0;l<NrPixels;l++) Image[(NrPixels*k)+l] = ImageTemp2[k][l];
	FreeMemMatrixPx(ImageTemp1,NrPixels);
	FreeMemMatrixPx(ImageTemp2,NrPixels);
}

static void
check (int test, const char * message, ...)
{
    if (test) {
        va_list args;
        va_start (args, message);
        vfprintf (stderr, message, args);
        va_end (args);
        fprintf (stderr, "\n");
        exit (EXIT_FAILURE);
    }
}

int main(int argc, char *argv[]){
	clock_t start, end;
	if (argc != 4){
		printf("Not enough arguments, exiting.\n");
		return 1;
	}
    double diftotal;
    start = clock();
    // Read params file.
    char *ParamFN;
    FILE *fileParam;
    ParamFN = argv[1];
    char aline[1000];
    fflush(stdout);
    fileParam = fopen(ParamFN,"r");
    if (fileParam == NULL){
		printf("Parameter file could not be read. Exiting\n");
		return 1;
	}
    check (fileParam == NULL,"%s file not found: %s", ParamFN, strerror(errno));
    char *str, dummy[1000], Folder[1024], FileStem[1024], *TmpFolder, darkcurrentfilename[1024], floodfilename[1024], Ext[1024],RawFolder[1024];
    TmpFolder = "Temp";
    int LowNr,FileNr,RingNr;
    FileNr = atoi(argv[2]);
    RingNr = atoi(argv[3]);
    double Thresh, bc=1, Ycen, Zcen, IntSat, OmegaStep, OmegaFirstFile, Lsd, px, Width, Wavelength, LatticeConstant,MaxRingRad;
    int CellStruct,NrPixels,Padding = 6, StartNr;
    char fs[1024];
    int LayerNr;
    int NrTransOpt=0;
    int TransOpt[10];
    int StartFileNr, NrFilesPerSweep;
    int DoFullImage = 0;
    int FrameNrOmeChange = 1;
    double OmegaMissing = 0, MisDir;
    while (fgets(aline,1000,fileParam)!=NULL){
		printf("%s\n",aline);
		fflush(stdout);
        str = "StartFileNr ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &StartFileNr);
            continue;
        }
        str = "DoFullImage ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &DoFullImage);
            continue;
        }
        str = "NrFilesPerSweep ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &NrFilesPerSweep);
            continue;
        }
        str = "Ext ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, Ext);
            continue;
        }
        str = "RawFolder ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, RawFolder);
            continue;
        }
        str = "Folder ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, Folder);
            continue;
        }
        str = "FileStem ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, fs);
            continue;
        }
        str = "Dark ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, darkcurrentfilename);
            continue;
        }
        str = "Flood ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, floodfilename);
            continue;
        }
        str = "LowerBoundThreshold ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &Thresh);
            continue;
        }
        str = "BeamCurrent ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &bc);
            continue;
        }
        str = "BC ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf %lf", dummy, &Ycen, &Zcen);
            continue;
        }
        str = "UpperBoundThreshold ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &IntSat);
            continue;
        }
        str = "OmegaStep ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &OmegaStep);
            continue;
        }
        str = "OmegaFirstFile ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &OmegaFirstFile);
            continue;
        }
        str = "px ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &px);
            continue;
        }
        str = "Width ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &Width);
            continue;
        }
        str = "LayerNr ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &LayerNr);
            continue;
        }
        str = "CellStruct ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &CellStruct);
            continue;
        }
        str = "NrPixels ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &NrPixels);
            continue;
        }
        str = "Padding ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &Padding);
            continue;
        }
        str = "Wavelength ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &Wavelength);
            continue;
        }
        str = "Lsd ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &Lsd);
            continue;
        }
        str = "StartNr ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &StartNr);
            continue;
        }
        str = "MaxRingRad ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &MaxRingRad);
            continue;
        }
        str = "ImTransOpt ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &TransOpt[NrTransOpt]);
            NrTransOpt++;
            continue;
        }
        str = "FrameOmeChange ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d %lf %lf", dummy, &FrameNrOmeChange, &OmegaMissing, &MisDir);
            continue;
        }
	}
	printf("%f\n",Thresh);
	Width = Width/px;
	int i,j,k;
    for (i=0;i<NrTransOpt;i++){
        if (TransOpt[i] < 0 || TransOpt[i] > 3){printf("TransformationOptions can only be 0, 1, 2 or 3.\nExiting.\n");return 0;}
        printf("TransformationOptions: %d ",TransOpt[i]);
        if (TransOpt[i] == 0) printf("No change.\n");
        else if (TransOpt[i] == 1) printf("Flip Left Right.\n");
        else if (TransOpt[i] == 2) printf("Flip Top Bottom.\n");
        else printf("Transpose.\n");
    }
	sprintf(FileStem,"%s_%d",fs,LayerNr);
	fclose(fileParam);
	double MaxTtheta = rad2deg*atan(MaxRingRad/Lsd);
	double RingRad;
	char hklfn[2040];
	sprintf(hklfn,"%s/hkls.csv",Folder);
	FILE *hklf = fopen(hklfn,"r");
    if (hklf == NULL){
		printf("HKL file could not be read. Exiting\n");
		return 1;
	}
	fgets(aline,1000,hklf);
	int Rnr;
	double RRd;
	while (fgets(aline,1000,hklf)!=NULL){
		sscanf(aline, "%s %s %s %s %d %s %s %s %s %s %lf",dummy,dummy,dummy,dummy,&Rnr,dummy,dummy,dummy,dummy,dummy,&RRd);
		if (Rnr == RingNr){
			RingRad = RRd;
			break;
		}
	}
	RingRad = RingRad/px;
	printf("RingNr = %d RingRad = %f\n",RingNr, RingRad);
	double Rmin=RingRad-Width, Rmax=RingRad+Width;
	double Omega;
	int Nadditions;
	if (FileNr - StartNr + 1 < FrameNrOmeChange){
    	Omega = OmegaFirstFile + ((FileNr-StartNr)*OmegaStep);
    } else {
        Nadditions = (int) ((FileNr - StartNr + 1) / FrameNrOmeChange)  ;
        Omega = OmegaFirstFile + ((FileNr-StartNr)*OmegaStep) + MisDir*OmegaMissing*Nadditions;
    }
	double *dark,*flood, *darkTemp;;
	//printf("%f %f\n",Rmin,Rmax);
	dark = malloc(NrPixels*NrPixels*sizeof(*dark));
	darkTemp = malloc(NrPixels*NrPixels*sizeof(*darkTemp));
	flood = malloc(NrPixels*NrPixels*sizeof(*flood));
	FILE *darkfile=fopen(darkcurrentfilename,"rb");
	int sz, nFrames;
	int SizeFile = sizeof(pixelvalue) * NrPixels * NrPixels;
	long int Skip;
	for (i=0;i<(NrPixels*NrPixels);i++){dark[i]=0;darkTemp[i]=0;}
	pixelvalue *darkcontents;
	darkcontents = malloc(NrPixels*NrPixels*sizeof(*darkcontents));
	if (darkfile==NULL){printf("Could not read the dark file. Using no dark subtraction.");}
	else{
		fseek(darkfile,0L,SEEK_END);
		sz = ftell(darkfile);
		rewind(darkfile);
		nFrames = sz/(8*1024*1024);
		Skip = sz - (nFrames*8*1024*1024);
		fseek(darkfile,Skip,SEEK_SET);
		printf("Reading dark file: %s, nFrames: %d, skipping first %ld bytes.\n",darkcurrentfilename,nFrames,Skip);
		for (i=0;i<nFrames;i++){
			fread(darkcontents,SizeFile,1,darkfile);
			DoImageTransformations(NrTransOpt,TransOpt,darkcontents,NrPixels);
			for (j=0;j<(NrPixels*NrPixels);j++){
				darkTemp[j] += darkcontents[j];
			}
		}
		fclose(darkfile);
		for (i=0;i<(NrPixels*NrPixels);i++){
			darkTemp[i] /= nFrames;
		}
	}
	Transposer(darkTemp,NrPixels,dark);
	free(darkcontents);
	FILE *floodfile=fopen(floodfilename,"rb");
	if (floodfile==NULL){
		printf("Could not read the flood file. Using no flood correction.\n");
		for(i=0;i<(NrPixels*NrPixels);i++){
			flood[i]=1;
		}
	}
	else{
		fread(flood,sizeof(double)*NrPixels*NrPixels, 1, floodfile);
		fclose(floodfile);
	}
	double Rt;
	int *GoodCoords;
	GoodCoords = malloc(NrPixels*NrPixels*sizeof(*GoodCoords));
	memset(GoodCoords,0,NrPixels*NrPixels*sizeof(*GoodCoords));
	for (i=1;i<NrPixels;i++){
		for (j=1;j<NrPixels;j++){
			Rt = sqrt((i-Ycen)*(i-Ycen)+(j-Zcen)*(j-Zcen));
			if (Rt > Rmin && Rt < Rmax){GoodCoords[((i-1)*NrPixels)+(j-1)] = 1;}
			else {GoodCoords[((i-1)*NrPixels)+(j-1)] = 0;}
		}
	}
	if (DoFullImage == 1){
		for (i=0;i<NrPixels*NrPixels;i++) GoodCoords[i] = 1;
	}
	
	// Get nFrames:
	FILE *dummyFile;
	char dummyFN[2048];
	if (Padding == 2){sprintf(dummyFN,"%s/%s_%02d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 3){sprintf(dummyFN,"%s/%s_%03d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 4){sprintf(dummyFN,"%s/%s_%04d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 5){sprintf(dummyFN,"%s/%s_%05d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 6){sprintf(dummyFN,"%s/%s_%06d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 7){sprintf(dummyFN,"%s/%s_%07d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 8){sprintf(dummyFN,"%s/%s_%08d%s",RawFolder,fs,StartFileNr,Ext);}
	else if (Padding == 9){sprintf(dummyFN,"%s/%s_%09d%s",RawFolder,fs,StartFileNr,Ext);}
	dummyFile = fopen(dummyFN,"rb");
	if (dummyFile == NULL){
		printf("Could not read the input file %s. Exiting.\n",dummyFN);
		return 1;
	}
	fseek(dummyFile,0L,SEEK_END);
	sz = ftell(dummyFile);
	fclose(dummyFile);
	nFrames = sz/(8*1024*1024);

	char FN[2048];
	int ReadFileNr;
	ReadFileNr = StartFileNr + ((FileNr-1) / nFrames);
	int FramesToSkip = ((FileNr-1) % nFrames);
	
	if (Padding == 2){sprintf(FN,"%s/%s_%02d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 3){sprintf(FN,"%s/%s_%03d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 4){sprintf(FN,"%s/%s_%04d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 5){sprintf(FN,"%s/%s_%05d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 6){sprintf(FN,"%s/%s_%06d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 7){sprintf(FN,"%s/%s_%07d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 8){sprintf(FN,"%s/%s_%08d%s",RawFolder,fs,ReadFileNr,Ext);}
	else if (Padding == 9){sprintf(FN,"%s/%s_%09d%s",RawFolder,fs,ReadFileNr,Ext);}

	printf("Reading file: %s\n",FN);
	FILE *ImageFile = fopen(FN,"rb");
	if (ImageFile == NULL){
		printf("Could not read the input file. Exiting.\n");
		return 1;
	}
	pixelvalue *Image;
	Image = malloc(NrPixels*NrPixels*sizeof(*Image));
	fseek(ImageFile,0L,SEEK_END);
	sz = ftell(ImageFile);
	rewind(ImageFile);
	Skip = sz - ((nFrames-FramesToSkip) * 8*1024*1024);
	printf("Now processing file: %s\n",FN);
	double beamcurr=1;
	fseek(ImageFile,Skip,SEEK_SET);
	fread(Image,SizeFile,1,ImageFile);
	fclose(ImageFile);
	DoImageTransformations(NrTransOpt,TransOpt,Image,NrPixels);
	printf("Beam current this file: %f, Beam current scaling value: %f\n",beamcurr,bc);
	double *ImgCorrBCTemp, *ImgCorrBC;
	ImgCorrBC = malloc(NrPixels*NrPixels*sizeof(*ImgCorrBC));
	ImgCorrBCTemp = malloc(NrPixels*NrPixels*sizeof(*ImgCorrBCTemp));
	for (i=0;i<(NrPixels*NrPixels);i++)ImgCorrBCTemp[i]=Image[i];
	free(Image);
	Transposer(ImgCorrBCTemp,NrPixels,ImgCorrBC);
	for (i=0;i<(NrPixels*NrPixels);i++){
		ImgCorrBC[i] = (ImgCorrBC[i] - dark[i])/flood[i];
		ImgCorrBC[i] = ImgCorrBC[i]*bc/beamcurr;
		if (ImgCorrBC[i] < Thresh){
			ImgCorrBC[i] = 0;
		}
		if (GoodCoords[i] == 0){
			ImgCorrBC[i] = 0;
		}
	}
	free(GoodCoords);
	free(ImgCorrBCTemp);
	free(dark);
	free(flood);
	char OutFolderName[1024];
	sprintf(OutFolderName,"%s/%s",Folder,TmpFolder);
	int e = CheckDirectoryCreation(OutFolderName);
	if (e == 0){ return 1;}
	int Displace = 1;
	int sizeIncr = 1;
	int RegIncr = 3;
	int nOverlapsMaxPerImage = 10000;
	int NumberOfFilesPerSweep = 1;
	// Do Connected components
	int **BoolImage, **ConnectedComponents;
	BoolImage = allocMatrixInt(NrPixels,NrPixels);
	ConnectedComponents = allocMatrixInt(NrPixels,NrPixels);
	int **Positions;
	Positions = allocMatrixInt(nOverlapsMaxPerImage,NrPixels*4);
	int *PositionTrackers;
	PositionTrackers = malloc(nOverlapsMaxPerImage*sizeof(*PositionTrackers));
	for (i=0;i<nOverlapsMaxPerImage;i++)PositionTrackers[i] = 0;
	int NrOfReg;
	for (i=0;i<NrPixels;i++){
		for (j=0;j<NrPixels;j++){
			if (ImgCorrBC[(i*NrPixels)+j] != 0){
				BoolImage[i][j] = 1;
			}else{
				BoolImage[i][j] = 0;
			}
		}
	}
	NrOfReg = FindConnectedComponents(BoolImage,NrPixels,ConnectedComponents,Positions,PositionTrackers);
	FreeMemMatrixInt(BoolImage,NrPixels);
	/*FILE *connectedcomps;
	char conncomp[1024];
	pixelvalue *CCP;
	CCP = malloc(NrPixels*NrPixels*sizeof(*CCP));
	memset(CCP,0,NrPixels*NrPixels*sizeof(*CCP));
	for (i=0;i<NrPixels;i++){
		for (j=0;j<NrPixels;j++){
			if (ConnectedComponents[i][j] != 0){
				CCP[(i*NrPixels)+j] = ConnectedComponents[i][j];
			}
		}
	}
	sprintf(conncomp,"%sccp",FN);
	connectedcomps = fopen(conncomp,"w");
	fwrite(CCP,NrPixels*NrPixels*sizeof(pixelvalue),1,connectedcomps);
	fclose(connectedcomps);
	free(CCP);*/
	FreeMemMatrixInt(ConnectedComponents,NrPixels);
	int RegNr,NrPixelsThisRegion;
	int **MaximaPositions;
	double *MaximaValues;
	int **UsefulPixels;
	double *z;
	MaximaPositions = allocMatrixInt(NrPixels*10,2);
	MaximaValues = malloc(NrPixels*10*sizeof(*MaximaValues));
	UsefulPixels = allocMatrixInt(NrPixels*10,2);
	z = malloc(NrPixels*10*sizeof(*z));
	int IsSaturated;
	int SpotIDStart = 1;
	char OutFile[1024];
	if (Padding == 2) {sprintf(OutFile,"%s/%s_%02d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 3) {sprintf(OutFile,"%s/%s_%03d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 4) {sprintf(OutFile,"%s/%s_%04d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 5) {sprintf(OutFile,"%s/%s_%05d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 6) {sprintf(OutFile,"%s/%s_%06d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 7) {sprintf(OutFile,"%s/%s_%07d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 8) {sprintf(OutFile,"%s/%s_%08d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	else if (Padding == 9) {sprintf(OutFile,"%s/%s_%09d_%d_PS.csv",OutFolderName,FileStem,FileNr,RingNr);}
	FILE *outfilewrite;
	outfilewrite = fopen(OutFile,"w");
	fprintf(outfilewrite,"SpotID IntegratedIntensity Omega(degrees) YCen(px) ZCen(px) IMax Radius(px) Eta(degrees) SigmaR SigmaEta\n");
	int TotNrRegions = NrOfReg;
	double TotInt;
	for (RegNr=1;RegNr<=NrOfReg;RegNr++){
		NrPixelsThisRegion = PositionTrackers[RegNr];
		if (NrPixelsThisRegion == 1){
			TotNrRegions--;
			continue;
		}
		TotInt = 0;
		for (i=0;i<NrPixelsThisRegion;i++){
			UsefulPixels[i][0] = (int)(Positions[RegNr][i]/NrPixels);
			UsefulPixels[i][1] = (int)(Positions[RegNr][i]%NrPixels);
			z[i] = ImgCorrBC[((UsefulPixels[i][0])*NrPixels) + (UsefulPixels[i][1])];
			TotInt += z[i];
		}
		unsigned nPeaks;
		nPeaks = FindRegionalMaxima(z,UsefulPixels,NrPixelsThisRegion,MaximaPositions,MaximaValues,&IsSaturated,IntSat);
		if (IsSaturated == 1){ //Saturated peaks removed
			TotNrRegions--;
			continue;
		}
		double *IntegratedIntensity, *IMAX, *YCEN, *ZCEN, *Rads, *Etass, *OtherInfo;
		IntegratedIntensity = malloc(nPeaks*2*sizeof(*IntegratedIntensity));
		memset(IntegratedIntensity,0,nPeaks*2*sizeof(*IntegratedIntensity));
		IMAX = malloc(nPeaks*2*sizeof(*IMAX));
		YCEN = malloc(nPeaks*2*sizeof(*YCEN));
		ZCEN = malloc(nPeaks*2*sizeof(*ZCEN));
		Rads = malloc(nPeaks*2*sizeof(*Rads));
		Etass = malloc(nPeaks*2*sizeof(*Etass));
		OtherInfo = malloc(nPeaks*10*sizeof(*OtherInfo));
		int *NrPx;
		NrPx = malloc(nPeaks*2*sizeof(*NrPx));
		printf("%d %d %d %d\n",RegNr,NrOfReg,NrPixelsThisRegion,nPeaks);
		Fit2DPeaks(nPeaks,NrPixelsThisRegion,z,UsefulPixels,MaximaValues,MaximaPositions,IntegratedIntensity,IMAX,YCEN,ZCEN,Rads,Etass,Ycen,Zcen,Thresh,NrPx,OtherInfo);
		for (i=0;i<nPeaks;i++){
			fprintf(outfilewrite,"%d %f %f %f %f %f %f %f ",(SpotIDStart+i),IntegratedIntensity[i],Omega,YCEN[i]+Ycen,ZCEN[i]+Zcen,IMAX[i],Rads[i],Etass[i]);
			for (j=0;j<2;j++) fprintf(outfilewrite, "%f ",OtherInfo[2*i+j]);
			fprintf(outfilewrite,"\n");
		}
		SpotIDStart += nPeaks;
		free(IntegratedIntensity);
		free(IMAX);
		free(YCEN);
		free(ZCEN);
		free(Rads);
		free(Etass);
		free(NrPx);
	}
	printf("Number of regions = %d\n",TotNrRegions);
	printf("Number of peaks = %d\n",SpotIDStart-1);
	fclose(outfilewrite);
	free(ImgCorrBC);
	free(PositionTrackers);
	free(z);
	free(MaximaValues);
    //FreeMemMatrixInt(Positions,nOverlapsMaxPerImage);
	FreeMemMatrixInt(MaximaPositions,NrPixels*10);
	FreeMemMatrixInt(UsefulPixels,NrPixels*10);
	end = clock();
	diftotal = ((double)(end-start))/CLOCKS_PER_SEC;
    printf("Time elapsed: %f s.\n",diftotal);
    return 0;
}