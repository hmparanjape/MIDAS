#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <ctype.h>
#include <nlopt.h>
#include <stdint.h>
#include <sys/mman.h> 
#include <errno.h>
#include <stdarg.h>
#include <sys/ipc.h>
#include <sys/shm.h>

#define RealType double
#define float32_t float
#define SetBit(A,k)   (A[(k/32)] |=  (1 << (k%32)))
#define ClearBit(A,k) (A[(k/32)] &= ~(1 << (k%32)))
#define TestBit(A,k)  (A[(k/32)] &   (1 << (k%32)))
#define deg2rad 0.0174532925199433
#define rad2deg 57.2957795130823
#define EPS 1E-5
#define MAX_N_SPOTS 500
#define MAX_N_OMEGA_RANGES 20
#define MAX_POINTS_GRID_GOOD 300000

int Flag = 0;

double**
allocMatrixF(int nrows, int ncols)
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

int**
allocMatrixIntF(int nrows, int ncols)
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

struct my_func_data{
	int NrOfFiles;
    int nLayers;
    double ExcludePoleAngle;
    long long int SizeObsSpots;
    double XGrain[3];
    double YGrain[3];
    double OmegaStart;
    double OmegaStep;
    double px;
    double gs;
    double hkls[5000][4];
    int n_hkls;
    double Thetas[5000];
    int NoOfOmegaRanges;
    int NrPixelsGrid;
    double OmegaRanges[MAX_N_OMEGA_RANGES][2];
    double BoxSizes[MAX_N_OMEGA_RANGES][4];
    double **P0;
    int *ObsSpotsInfo;
    double *Lsd;
    double RotMatTilts[3][3];
    double *ybc;
    double *zbc;
};

static
double problem_function(
    unsigned n,
	const double *x,
	double *grad,
	void* f_data_trial)
{
	struct my_func_data *f_data = (struct my_func_data *) f_data_trial;
	int i, j, count = 1;
	const int NrOfFiles = f_data->NrOfFiles;
    const int nLayers = f_data->nLayers;
    const double ExcludePoleAngle = f_data->ExcludePoleAngle;
    const long long int SizeObsSpots = f_data->SizeObsSpots;
    double XGrain[3];
    double YGrain[3];
    const double OmegaStart = f_data->OmegaStart;
    const double OmegaStep = f_data->OmegaStep;
    const double px = f_data->px;
    const double gs = f_data->gs;
    const int NoOfOmegaRanges = f_data->NoOfOmegaRanges;
    const int NrPixelsGrid = f_data->NrPixelsGrid;
    double P0[nLayers][3];
    double OmegaRanges[MAX_N_OMEGA_RANGES][2];
    double BoxSizes[MAX_N_OMEGA_RANGES][4];
    double hkls[5000][4];
    int n_hkls = f_data->n_hkls;
    double Thetas[5000];
    for (i=0;i<5000;i++){
		hkls[i][0] = f_data->hkls[i][0];
		hkls[i][1] = f_data->hkls[i][1];
		hkls[i][2] = f_data->hkls[i][2];
		hkls[i][3] = f_data->hkls[i][3];
		Thetas[i] = f_data->Thetas[i];
	}
    int *ObsSpotsInfo;
	ObsSpotsInfo = &(f_data->ObsSpotsInfo[0]);
	double *Lsd;
	Lsd = &(f_data->Lsd[0]);
	double *ybc;
	ybc = &(f_data->ybc[0]);
	double *zbc;
	zbc = &(f_data->zbc[0]);
	for (i=0;i<3;i++){
		XGrain[i] = f_data->XGrain[i];
		YGrain[i] = f_data->YGrain[i];
		for (j=0;j<nLayers;j++){
			P0[j][i] = f_data->P0[j][i];
		}
	}
	for (i=0;i<MAX_N_OMEGA_RANGES;i++){
		for (j=0;j<2;j++){
			OmegaRanges[i][j] = f_data->OmegaRanges[i][j];
		}
		for (j=0;j<4;j++){
			BoxSizes[i][j] = f_data->BoxSizes[i][j];
		}
	}
	double RotMatTilts[3][3];
	for (i=0;i<3;i++){
		for (j=0;j<3;j++){
			RotMatTilts[i][j] = f_data->RotMatTilts[i][j];
		}
	}
    double OrientMatIn[3][3], FracOverlap, x2[3];
    x2[0] = x[0]; x2[1] = x[1]; x2[2] = x[2];
    Euler2OrientMat(x2,OrientMatIn);
    CalcOverlapAccOrient(NrOfFiles,nLayers,ExcludePoleAngle,Lsd,SizeObsSpots,XGrain,
		YGrain,RotMatTilts,OmegaStart,OmegaStep,px,ybc,zbc,gs,hkls,n_hkls,
		Thetas,OmegaRanges,NoOfOmegaRanges,BoxSizes,P0,NrPixelsGrid,
		ObsSpotsInfo,OrientMatIn,&FracOverlap);
    return (1 - FracOverlap);
}

void
FitOrientation(
    const int NrOfFiles,
    const int nLayers,
    const double ExcludePoleAngle,
    double Lsd[nLayers],
    const long long int SizeObsSpots,
    const double XGrain[3],
    const double YGrain[3],
    double RotMatTilts[3][3],
    const double OmegaStart,
    const double OmegaStep,
    const double px,
    double ybc[nLayers],
    double zbc[nLayers],
    const double gs,
    double OmegaRanges[MAX_N_OMEGA_RANGES][2],
    const int NoOfOmegaRanges,
    double BoxSizes[MAX_N_OMEGA_RANGES][4],
    double P0[nLayers][3],
    const int NrPixelsGrid,
    int *ObsSpotsInfo,
    double EulerIn[3],
    double tol,
    double *EulerOutA,
    double *EulerOutB,
    double *EulerOutC,
    double *ResultFracOverlap,
    double hkls[5000][4],
    double Thetas[5000],
    int n_hkls)
{
	unsigned n;
    long int i,j;
    n  = 3;
    double x[n],xl[n],xu[n];
    for( i=0; i<n; i++)
    {
        x[i] = EulerIn[i];
        xl[i] = x[i] - (tol*M_PI/180);
        xu[i] = x[i] + (tol*M_PI/180);
    }
	struct my_func_data f_data;
	f_data.NrOfFiles = NrOfFiles;
	f_data.nLayers = nLayers;
	f_data.n_hkls = n_hkls;
	for (i=0;i<5000;i++){
		f_data.hkls[i][0] = hkls[i][0];
		f_data.hkls[i][1] = hkls[i][1];
		f_data.hkls[i][2] = hkls[i][2];
		f_data.hkls[i][3] = hkls[i][3];
		f_data.Thetas[i] = Thetas[i];
	}
	f_data.ExcludePoleAngle = ExcludePoleAngle;
	f_data.SizeObsSpots = SizeObsSpots;
	f_data.P0 = allocMatrixF(nLayers,3);
	for (i=0;i<3;i++){
		f_data.XGrain[i] = XGrain[i];
		f_data.YGrain[i] = YGrain[i];
		for (j=0;j<nLayers;j++){
			f_data.P0[j][i] = P0[j][i];
		}
		for (j=0;j<3;j++){
			f_data.RotMatTilts[i][j] = RotMatTilts[i][j];
		}
	}
	for (i=0;i<MAX_N_OMEGA_RANGES;i++){
		for (j=0;j<2;j++){
			f_data.OmegaRanges[i][j] = OmegaRanges[i][j];
		}
		for (j=0;j<4;j++){
			f_data.BoxSizes[i][j] = BoxSizes[i][j];
		}
	}
	f_data.ObsSpotsInfo = &ObsSpotsInfo[0];
	f_data.Lsd = &Lsd[0];
	f_data.ybc = &ybc[0];
	f_data.zbc = &zbc[0];
	f_data.OmegaStart = OmegaStart;
	f_data.OmegaStep = OmegaStep;
	f_data.px = px;
	f_data.gs = gs;
	f_data.NoOfOmegaRanges = NoOfOmegaRanges;
	f_data.NrPixelsGrid = NrPixelsGrid;
	struct my_func_data *f_datat;
	f_datat = &f_data;
	void* trp = (struct my_func_data *) f_datat;
	double tole = 1e-3;
	nlopt_opt opt;
	opt = nlopt_create(NLOPT_LN_NELDERMEAD, n);	
	nlopt_set_lower_bounds(opt, xl);
	nlopt_set_upper_bounds(opt, xu);
	nlopt_set_min_objective(opt, problem_function, trp);
	double minf=1;
	nlopt_optimize(opt, x, &minf);
	nlopt_destroy(opt);
    *ResultFracOverlap = minf;
    *EulerOutA = x[0];
    *EulerOutB = x[1];
    *EulerOutC = x[2];
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


int
main(int argc, char *argv[])
{
    clock_t start, end;
    double diftotal;
    start = clock();
    
    // Read params file.
    char *ParamFN;
    FILE *fileParam;
    ParamFN = argv[1];
    int rown=atoi(argv[2]);
    char *MicFN = argv[3];
    char aline[1000];
    fileParam = fopen(ParamFN,"r");
    char *str, dummy[1000];
    int LowNr,nLayers;
    double tx,ty,tz;
    while (fgets(aline,1000,fileParam)!=NULL){
        str = "nDistances ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &nLayers);
            break;
        }
    }
    rewind(fileParam);
    double Lsd[nLayers],ybc[nLayers],zbc[nLayers],ExcludePoleAngle,
		LatticeConstant[6],Wavelength, minFracOverlap,doubledummy,
		MaxRingRad,MaxTtheta;
    double px, OmegaStart,OmegaStep,tol;
	char fn[1000];
	char fn2[1000];
	char direct[1000];
    double OmegaRanges[MAX_N_OMEGA_RANGES][2], BoxSizes[MAX_N_OMEGA_RANGES][4];
    int cntr=0,countr=0,conter=0,StartNr,EndNr,intdummy,SpaceGroup;
    int NoOfOmegaRanges=0;
    while (fgets(aline,1000,fileParam)!=NULL){
		str = "ReducedFileName ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, fn2);
            continue;
        }
		str = "DataDirectory ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %s", dummy, direct);
            continue;
        }
        str = "Lsd ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &Lsd[cntr]);
            cntr++;
            continue;
        }
        str = "SpaceGroup ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &SpaceGroup);
            continue;
        }
        str = "MaxRingRad ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &MaxRingRad);
            continue;
        }
        str = "StartNr ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &StartNr);
            continue;
        }
        str = "EndNr ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %d", dummy, &EndNr);
            continue;
        }
        str = "ExcludePoleAngle ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &ExcludePoleAngle);
            continue;
        }
        str = "LatticeParameter ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf %lf %lf %lf %lf %lf", dummy, 
				&LatticeConstant[0],&LatticeConstant[1],
				&LatticeConstant[2],&LatticeConstant[3],
				&LatticeConstant[4],&LatticeConstant[5]);
            continue;
        }
        str = "tx ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &tx);
            continue;
        }
        str = "ty ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &ty);
            continue;
        }
        str = "BC ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf %lf", dummy, &ybc[conter], &zbc[conter]);
            conter++;
            continue;
        }
        str = "tz ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &tz);
            continue;
        }
        str = "OrientTol ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &tol);
            continue;
        }
        str = "MinFracAccept ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &minFracOverlap);
            continue;
        }
        str = "OmegaStart ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &OmegaStart);
            continue;
        }
        str = "OmegaStep ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &OmegaStep);
            continue;
        }
        str = "Wavelength ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &Wavelength);
            continue;
        }
        str = "px ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf", dummy, &px);
            continue;
        }
        str = "OmegaRange ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf %lf", dummy, &OmegaRanges[NoOfOmegaRanges][0],&OmegaRanges[NoOfOmegaRanges][1]);
            NoOfOmegaRanges++;
            continue;
        }
        str = "BoxSize ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            sscanf(aline,"%s %lf %lf %lf %lf", dummy, &BoxSizes[countr][0], &BoxSizes[countr][1], &BoxSizes[countr][2], &BoxSizes[countr][3]);
            countr++;
            continue;
        }
        str = "Ice9Input ";
        LowNr = strncmp(aline,str,strlen(str));
        if (LowNr==0){
            Flag = 1;
            continue;
        }  
    }
    fclose(fileParam);
    MaxTtheta = rad2deg*atan(MaxRingRad/Lsd[0]);
    //Read bin files
    char fnG[1000];
    sprintf(fnG,"%s/grid.txt",direct);
    char fnDS[1000];
    char fnKey[1000];
    char fnOr[1000];
    sprintf(fnDS,"%s/DiffractionSpots.txt",direct);
    sprintf(fnKey,"%s/Key.txt",direct);
    sprintf(fnOr,"%s/OrientMat.txt",direct);
    int i,j,m,nrFiles,nrPixels;
    char *ext="bin";
    int *ObsSpotsInfo;
    nrFiles = EndNr - StartNr + 1;
    nrPixels = 2048*2048;
    long long int SizeObsSpots;
    SizeObsSpots = (nLayers);
    SizeObsSpots*=nrPixels;
    SizeObsSpots*=nrFiles;
    SizeObsSpots/=32;
    
    // Read spots info
	char *file_name = "/dev/shm/SpotsInfo.bin";
    int descp;
    struct stat s;
    int status;
    size_t size;
    int rc;
    descp = open (file_name, O_RDONLY);
    check (descp < 0, "open %s failed: %s", file_name, strerror (errno));
    status = fstat (descp, & s);
    check (status < 0, "stat %s failed: %s", file_name, strerror (errno));
    size = s.st_size;
    ObsSpotsInfo = mmap (0, size, PROT_READ, MAP_SHARED, descp, 0);
    check (ObsSpotsInfo == MAP_FAILED, "mmap %s failed: %s",file_name, strerror (errno));
    
    //Read position.
    FILE *fp;
    fp = fopen(fnG,"r");
    char line[1024];
    fgets(line,1000,fp);
    int TotalNrSpots=0;
    sscanf(line,"%d",&TotalNrSpots);
    if (rown > TotalNrSpots){
        printf("Error: Grid point number greater than total number of grid points.\n");
        return 0;
    }
    int counter=0;
    double y1,y2,xs,ys,gs;
    double **XY;
    XY = allocMatrixF(3,3);
    while(counter<rown){
        fgets(line,1000,fp);
        counter+=1;
    }
    sscanf(line,"%lf %lf %lf %lf %lf",&y1,&y2,&xs,&ys,&gs);
    fclose(fp);
    int UD;
    if (y1>y2){
		UD = -1;
        XY[0][0] =xs;
        XY[0][1] =ys - y1;
        XY[1][0] =xs - gs;
        XY[1][1] =ys + y2;
        XY[2][0] =xs + gs;
        XY[2][1] =ys + y2;
    }
    else{
		UD = 1;
        XY[0][0] =xs;
        XY[0][1] =ys + y2;
        XY[1][0] =xs - gs;
        XY[1][1] =ys - y1;
        XY[2][0] =xs + gs;
        XY[2][1] =ys - y1;
    }
    double GridSize=2*gs;

    //Read Key
    clock_t startthis;
    startthis = clock();
    FILE *fk;
    int NrOrientations,TotalDiffrSpots;
    fk = fopen(fnKey,"r");
    fgets(line,1000,fk);
    sscanf(line,"%d",&NrOrientations);
    int **NrSpots;
    NrSpots = allocMatrixIntF(NrOrientations,2);
    TotalDiffrSpots=0;
    for (i=0;i<NrOrientations;i++){
        fgets(line,1000,fk);
        sscanf(line,"%d",&NrSpots[i][0]);
        TotalDiffrSpots+=NrSpots[i][0];
        NrSpots[i][1] = TotalDiffrSpots - NrSpots[i][0];
    }
    fclose(fk);
    
    // Read DiffractionSpots
    double *SpotsMat;
    char *spfn = "/dev/shm/DiffractionSpots.bin";
    int spf;
    struct stat s2;
    int status2;
    size_t size2;
    int rc2;
    spf = open (spfn, O_RDONLY);
    check (spf < 0, "open %s failed: %s", spfn, strerror (errno));
    status2 = fstat (spf, & s2);
    check (status2 < 0, "stat %s failed: %s", spfn, strerror (errno));
    size2 = s2.st_size;
    SpotsMat = mmap (0, size2, PROT_READ, MAP_SHARED, spf, 0);
    check (SpotsMat == MAP_FAILED, "mmap %s failed: %s",spfn, strerror (errno));
    
    // Read OrientationMatrix
    double *OrientationMatrix;
    char *omfn = "/dev/shm/OrientMat.bin";
    int omf;
    struct stat s3;
    int status3;
    size_t size3;
    int rc3;
    omf = open (omfn, O_RDONLY);
    check (omf < 0, "open %s failed: %s", omfn, strerror (errno));
    status3 = fstat (omf, & s3);
    check (status3 < 0, "stat %s failed: %s", omfn, strerror (errno));
    size3 = s3.st_size;
    OrientationMatrix = mmap (0, size3, PROT_READ, MAP_SHARED, omf, 0);
    check (OrientationMatrix == MAP_FAILED, "mmap %s failed: %s",omfn, strerror (errno));

    // Go through each orientation and compare with observed spots.
    clock_t startthis2;
    startthis2 = clock();
    int NrPixelsGrid=2*(ceil((gs*2)/px))*(ceil((gs*2)/px));
    int NrSpotsThis,StartingRowNr;
    double FracOverT;
    double RotMatTilts[3][3], OrientationMatThis[9], OrientationMatThisUnNorm[9];
    RotationTilts(tx,ty,tz,RotMatTilts);
    double **OrientMatrix;
    OrientMatrix = allocMatrixF(MAX_POINTS_GRID_GOOD,10);
    int OrientationGoodID=0;
    double MatIn[3],P0[nLayers][3],P0T[3];
    double OrientMatIn[3][3],XG[3],YG[3];
    double ThrSps[MAX_N_SPOTS][3];
    MatIn[0]=0;
    MatIn[1]=0;
    MatIn[2]=0;
    for (i=0;i<nLayers;i++){
        MatIn[0] = -Lsd[i];
        MatrixMultF(RotMatTilts,MatIn,P0T);
        for (j=0;j<3;j++){
            P0[i][j] = P0T[j];
        }
    }
    for (j=0;j<3;j++){
        XG[j] = XY[j][0];
        YG[j] = XY[j][1];
    }
    printf("Checking orientation grid.\n");
    for (i=0;i<NrOrientations;i++){
        NrSpotsThis = NrSpots[i][0];
        StartingRowNr = NrSpots[i][1];
        m = 0;
        for (m=0;m<9;m++){
            OrientationMatThisUnNorm[m] = OrientationMatrix[i*9+m];
			if (OrientationMatThisUnNorm[m] == -0.0){
				OrientationMatThisUnNorm[m] = 0;
			}
        }
        m=0;
        NormalizeMat(OrientationMatThisUnNorm,OrientationMatThis);
        for (j=StartingRowNr;j<(StartingRowNr+NrSpotsThis);j++){
            ThrSps[m][0] = SpotsMat[j*3+0];
            ThrSps[m][1] = SpotsMat[j*3+1];
            ThrSps[m][2] = SpotsMat[j*3+2];
            m++;
        }
        Convert9To3x3(OrientationMatThis,OrientMatIn);
        CalcFracOverlap(nrFiles,nLayers,NrSpotsThis,ThrSps,OmegaStart,
			OmegaStep,XG,YG,Lsd,SizeObsSpots,RotMatTilts,px,ybc,zbc,
			gs,P0,NrPixelsGrid,ObsSpotsInfo,OrientMatIn,&FracOverT);
        if (FracOverT >= minFracOverlap){
            for (j=0;j<9;j++){
                OrientMatrix[OrientationGoodID][j] = OrientationMatThis[j];
            }
            OrientMatrix[OrientationGoodID][9] = FracOverT;
            OrientationGoodID++;
        }
    }
    printf("Finished checking orientation grid. Now fitting %d orientations.\n",OrientationGoodID);
    double BestFrac, BestEuler[3];
    if (OrientationGoodID>0){
		int n_hkls = 0;
		double hkls[5000][4];
		double Thetas[5000];
		char hklfn[1024];
		sprintf(hklfn,"%s/hkls.csv",direct);
		FILE *hklf = fopen(hklfn,"r");
		fgets(aline,1000,hklf);
		while (fgets(aline,1000,hklf)!=NULL){
			sscanf(aline, "%s %s %s %s %lf %lf %lf %lf %lf %s %s",dummy,dummy,dummy,
				dummy,&hkls[n_hkls][3],&hkls[n_hkls][0],&hkls[n_hkls][1],
				&hkls[n_hkls][2],&Thetas[n_hkls],dummy,dummy);
			n_hkls++;
		}
        double Fractions, EulerIn[3], OrientIn[3][3], FracOut, EulerOutA, EulerOutB,EulerOutC,OMTemp[9];
        BestFrac = -1;
        for (i=0;i<OrientationGoodID;i++){
            for (j=0;j<9;j++){
                OMTemp[j] = OrientMatrix[i][j];
            }
            Convert9To3x3(OMTemp,OrientIn);
            OrientMat2Euler(OrientIn,EulerIn);
            FitOrientation(nrFiles,nLayers,ExcludePoleAngle,Lsd,SizeObsSpots,
				XG,YG,RotMatTilts,OmegaStart,OmegaStep,px,ybc,zbc,gs,
				OmegaRanges,NoOfOmegaRanges,BoxSizes,P0,NrPixelsGrid,
				ObsSpotsInfo,EulerIn,tol,&EulerOutA,&EulerOutB,
				&EulerOutC,&FracOut,hkls,Thetas,n_hkls);
            Fractions = 1-FracOut;
            if (Fractions > BestFrac){
				printf("%f %d of %d, EulerAngles: %f %f %f\n",Fractions,i,OrientationGoodID,EulerOutA,EulerOutB,EulerOutC);
                BestFrac = Fractions;
                BestEuler[0] = EulerOutA;
                BestEuler[1] = EulerOutB;
                BestEuler[2] = EulerOutC;
                if (1-BestFrac < 0.0001) break;
            }
        }
    }else{
		printf("No good ID found.\n");
	}

    int result = open(MicFN, O_CREAT|O_WRONLY, S_IRUSR|S_IWUSR);
    if (result <= 0){
		printf("Could not open output file.\n");
		return 1;
	}
    end = clock();
    diftotal = ((double)(end-start))/CLOCKS_PER_SEC;
    double outresult[11] = {(double)atoi(argv[2]),(double)OrientationGoodID,
		diftotal,xs,ys,GridSize,(double)UD,BestEuler[0],BestEuler[1],
		BestEuler[2],BestFrac};
	int SizeWritten = 11*sizeof(double);
	int OffsetHere = (rown-1) * SizeWritten;
    int rc4 = pwrite(result,outresult,SizeWritten,OffsetHere);
    if (rc4 < 0){
		printf("Could not write to output file.\n");
		return 1;
	}else{
		printf("Written successfully to %s at %d\n",MicFN,OffsetHere);
		for (i=0;i<11;i++){
			printf("%f ",outresult[i]);
		}
		printf("\n");
	}
    printf("Time elapsed in comparing diffraction spots: %f [s]\n",diftotal);
    return 0;
}
