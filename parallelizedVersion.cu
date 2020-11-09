
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
extern "C" {
#include "ppm_lib.h"
}
#include <stdlib.h>
#include <time.h>
#include <stdio.h>
#include <math.h>
#include "string.h"
//Defini la taille du filtre (Sa dimension peut-etre de 3,5,7,9,11.....)
#define DIMFILTRE 5
#define rebord 6
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ < 200)
#define printf(f, ...) ((void)(f, __VA_ARGS__),0)
#endif
//Insere un pixel (tab de deux cases) dans un tableau à l'indice indiqué et decale toute les valeurs  se trouvant à droite de l'indice vers la droite
void insererDansTableauTrie(long *tab, int tailleTab, long tab2[2], int indice)
{
	int temp0;
	int temp1;
	for (int y = indice; y != tailleTab; y = y + 2)
	{
		temp0 = tab[y];
		tab[y] = tab2[0];
		tab2[0] = temp0;

		temp1 = tab[y + 1];
		tab[y + 1] = tab2[1];
		tab2[1] = temp1;
	}
}
//insere dans un tableau trié le pixel au bonne endroit et réalise les décalages nécéssaires
//Le tab est un tab 2D en 1D la premiere valeurs est la position du pixels et la deuxieme son poids
void rangerPixelDansTab(long *tab, long tab2[2], int tailleTab)
{
	for (int i = tailleTab - 2; i >= -2; i = i - 2)
	{
		if (tab[i + 1] >= tab2[1])
		{
			if (i == tailleTab - 2)
			{
				break;
			}
			insererDansTableauTrie(tab, tailleTab, tab2, i + 2);
			break;
		}
		if (i == 0)
		{
			insererDansTableauTrie(tab, tailleTab, tab2, i);
		}
	}
}

//La taille du filtre est modifiable, il faut aussi changé DIMFILTRE plus haut
__constant__ int filtre[DIMFILTRE*DIMFILTRE] = { 5,5,4,2,5,4,7,8,2,1,5,4,0,1,2,4,5,7,5,4,8,4,5,4,6 };

//Kernel permettant de calculer les Vij
//On prend autant de block que de ligne dans l'image, est 1024 thread. Chaque thread traitent 1 ou plusieurs pixels
__global__ void calculVijsSharedMemory(PPMPixel* tabPixels, long* valeurs, int* tailleImageX)
{
	//On est obligé de recuperer la taille de l'image car blockDim.x ne corespond pas forcément a la taille de l'image en X
	//Puisque dans le cas où l'image à une taille en x superieur à 1024 on ne peux pas prendre autant de thread que de pixel en largeur
	//threadIdx.x correspond au numero de la colonne et  blockIdx.x au numero de la ligne
	int TID = threadIdx.x + blockIdx.x * (*tailleImageX);
	int index = threadIdx.x;
	//Dans la version avec la memoire partagé, pour chaque block on met en mémoire partagé seulement les pixels qui seront utiles au calculs de Vij pour la ligne courante
	//On ne connait pas à l'avance la taille de ce tableau
	extern __shared__ PPMPixel pixelsProche[];
	//Chaque thread du block renseigne une colonne du tableau
	int indexmp = index;
	int TIDtmp = TID;
	while (indexmp < (*tailleImageX)) {
		for (int i = 0; i != DIMFILTRE; i++)
		{
			pixelsProche[indexmp + (i* (*tailleImageX))] = tabPixels[TIDtmp + (i* (*tailleImageX)) - ((DIMFILTRE / 2)*(*tailleImageX))];
		}
		indexmp += 1024;
		TIDtmp += 1024;
	}
	//On attends que tout les threads aient fini leurs travails
	__syncthreads();
	
	while (index < (*tailleImageX)) {
		//Si le numero du thread ne correspond  pas à un pixel sur les bords 
		if (index >= rebord && index < (*tailleImageX) - rebord && (blockIdx.x >= rebord) && blockIdx.x < (gridDim.x) - (rebord)) {
			//Calcul de V(i,j)
			int indiceFiltre = 0;
			for (int b = (-DIMFILTRE / 2); b != (DIMFILTRE / 2) + 1; b++) {
				for (int y = (-DIMFILTRE / 2); y != (DIMFILTRE / 2) + 1; y++) {
					int numeroPixel = index + ((DIMFILTRE / 2) * (*tailleImageX)) + (b * (*tailleImageX)) + y;
					valeurs[TID] += filtre[indiceFiltre] * (pixelsProche[numeroPixel].red + pixelsProche[numeroPixel].green);
					indiceFiltre++;
				}
			}
		}
		else
		{
			//V ij egale à 0 sur les bords
			valeurs[TID] = 0;
		}
		//Si l'image a plus de 1024 thread alors il faut continuer à traiter les pixels pas encore traités
		//Dans ce cas là le thread numero id va s'occuper de traiter le pixel id + 1024  (blockDim.x = 1024 )
		index += 1024;
		TID += 1024;
	}
}//Cache les characteres dans l'image
void cacherChars(PPMImage *img, char c[])
{

	//On recupere la taille de la chaine de chararactere
	int stringLength = strlen(c);
	int tailleTabPixel = 2 * 8 * strlen(c);
	//Tableau recuperant les n pixels les plus lourd
	long *tabPixels = (long *)malloc(tailleTabPixel * sizeof(long));
	//On initialise le tableau à 0
	for (int i = 0; i != tailleTabPixel; i++)
	{
		tabPixels[i] = 0;
	}


	PPMPixel *pixelsList = img->data;
	PPMPixel *dev_pixels;
	long *tabValeur = (long *)malloc(img->x*img->y * sizeof(long));
	long *dev_Valeurs;
	int tailleImgX = img->x;
	int *dev_TailleImgX;

	cudaMalloc((void**)&dev_pixels, img->x*img->y * sizeof(PPMPixel));
	cudaMalloc((void**)&dev_Valeurs, img->x*img->y * sizeof(long));
	cudaMalloc((void**)&dev_TailleImgX, sizeof(int));

	//Copie du tableau de pixels sur le GPU
	cudaMemcpy(dev_pixels, pixelsList, img->x*img->y * sizeof(PPMPixel), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_TailleImgX, &tailleImgX, sizeof(int), cudaMemcpyHostToDevice);

	//Lacement du kernel
	calculVijsSharedMemory << <(img->y), 1024 ,img->x*DIMFILTRE*sizeof(PPMPixel)>> > (dev_pixels, dev_Valeurs, dev_TailleImgX);
	
	//Copie du tableau de valeurs du GPU vers le CPU
	cudaMemcpy(tabValeur, dev_Valeurs, img->x*img->y * sizeof(long), cudaMemcpyDeviceToHost);

	/* liberer la memoire allouee sur le GPU */
	cudaFree(dev_pixels);
	cudaFree(dev_Valeurs);
	cudaFree(dev_TailleImgX);

	//On cherche les n pixels le plus grand Vij
	for (int v = 0; v != (img->x) * (img->y); v++)
	{

		if (tabValeur[v] != 0) {
			long tab[2] = { v,tabValeur[v] };
			rangerPixelDansTab(tabPixels, tab, tailleTabPixel);
		}
	}
	free(tabValeur);
	//Pour chaque caractere à coder : 
	for (int y = 0; y != stringLength; y++)
	{
		int dec = c[y];
		//Pour chaque bit
		for (int i = 0; i < 8; i++)
		{
			if (dec - pow(2, 7 - i) >= 0)
			{
				dec = dec - pow(2, 7 - i);
				//Si le bit a coder est 1 mais le bit de poids faible du bleu du pixel est 0 alors on le change en 1
				if (img->data[tabPixels[(i * 2) + (y * 8 * 2)]].blue % 2 == 0)
				{
					img->data[tabPixels[(i * 2) + (y * 8 * 2)]].blue += 1;

				}
			}
			else
			{
				//Si le bit a coder est 0 mais le bit de poids faible du bleu du pixel est 0 alors on le change en 1
				if (img->data[tabPixels[(i * 2) + (y * 8 * 2)]].blue % 2 != 0)
				{
					img->data[tabPixels[(i * 2) + (y * 8 * 2)]].blue -= 1;

				}
			}
		}
	}
}

//Trouve les characteres cachés dans l'image
void trouverChars(PPMImage *img, int nbChar)
{
	//Initialisation du tableau contenant les n valeurs les plus haute
	int tailleTabPixel = 2 * 8 * nbChar;
	//Ce tableau contient les n valeurs les plus lourdes ainsi que leur position coresspondante dans l'image
	long *tabPixels = (long *)malloc(tailleTabPixel * sizeof(long));
	//On initialise le tableau à 0
	for (int i = 0; i != tailleTabPixel; i++)
	{
		tabPixels[i] = 0;
	}

	PPMPixel *pixelsList = img->data;
	PPMPixel *dev_pixels;
	long *tabValeur = (long *)malloc(img->x*img->y * sizeof(long));
	long *dev_Valeurs;
	int tailleImgX = img->x;
	int *dev_TailleImgX;

	cudaMalloc((void**)&dev_pixels, img->x*img->y * sizeof(PPMPixel));
	cudaMalloc((void**)&dev_Valeurs, img->x*img->y * sizeof(long));
	cudaMalloc((void**)&dev_TailleImgX, sizeof(int));

	//Copie du tableau de pixels sur le GPU
	cudaMemcpy(dev_pixels, pixelsList, img->x*img->y * sizeof(PPMPixel), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_TailleImgX, &tailleImgX, sizeof(int), cudaMemcpyHostToDevice);
	//Lacement du kernel
	calculVijsSharedMemory << <(img->y), 1024, img->x*DIMFILTRE * sizeof(PPMPixel) >> > (dev_pixels, dev_Valeurs, dev_TailleImgX);

	//Copie du tableau de valeurs du GPU vers le CPU
	cudaMemcpy(tabValeur, dev_Valeurs, img->x*img->y * sizeof(long), cudaMemcpyDeviceToHost);
	/* liberer la memoire allouee sur le GPU */
	cudaFree(dev_pixels);
	cudaFree(dev_Valeurs);
	cudaFree(dev_TailleImgX);

	//On cherche les 8 pixels les plus <<lourds>>
	for (int v = 0; v != (img->x) * (img->y); v++)
	{

		if (tabValeur[v] != 0) {
			long tab[2] = { v,tabValeur[v] };
			rangerPixelDansTab(tabPixels, tab, tailleTabPixel);
		}
	}

	free(tabValeur);
	for (int y = 0; y != nbChar; y++)
	{
		//Pour chaque octet
		char* dest = (char *)malloc(8);
		for (int i = 0; i != 8; i++)
		{
			//Si le bit de poids faible de la couleur bleu est 0
			if (img->data[tabPixels[(i * 2) + (y * 8 * 2)]].blue % 2 == 0)
			{
				dest[i] = '0';
			}
			//Si le bit de poids faible de la couleur bleu est 1
			else
			{
				dest[i] = '1';
			}
		}
		char e = strtol(dest, (char **)NULL, 2);
		printf(" Charactere trouve : %c \n", e);
	}
}


int main() {
	cudaFree(0);
	PPMImage *image;
	//Ouverture de l'image
	image = readPPM("images/gare.ppm");
	//Chaine de char à cacher
	char c[] = "test cacher un char";
	//On affiche la taille du 
	printf("Largeur : %d hauteur : %d \n", image->x, image->y);
	int nbImage = 1;
	//On cache le char dans l'image
	clock_t d = clock();
	for(int i = 0; i != nbImage ; i++)
		cacherChars(image, c);
	clock_t f = clock();
	double time_taken = double(f - d) / double(CLOCKS_PER_SEC);
	printf("%f \n", time_taken);

	//On recherche les n char dans l'image 
	trouverChars(image, 19);

	return 0;
}


