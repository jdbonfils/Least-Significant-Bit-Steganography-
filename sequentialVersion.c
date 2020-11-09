#include "ppm_lib.h"
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <time.h>
#define TAILEFILTRE 25

//Insere une valeur dans un tableau a l'indice indiqué et decale toute les valeurs  se trouvant à droite de l'indice vers la droite
void insererDansTableauTrie(long *tab,int tailleTab, long tab2[2], int indice)
{
	int temp0;
	int temp1;
	for (int y = indice; y != tailleTab; y = y + 2)
	{
		temp0 = tab[y];
		tab[y] = tab2[0];
		tab2[0] = temp0;

		temp1 = tab[y+1];
		tab[y+1] = tab2[1];
		tab2[1] = temp1;
	}
}
//insere dans un tableau trié le pixel au bonne endroit et réalise les décalages nécéssaires
//Le tab est un tab 2D en 1D la premiere valeurs est la position du pixels et la deuxieme son poids
void rangerPixelDansTab(long *tab, long tab2[2], int tailleTab)
{
	for (int i = tailleTab-2; i >= -2; i = i -2)
	{
		if (tab[i + 1] >= tab2[1]  )
		{
			if (i == tailleTab-2)
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

//Cache le charactere dans l'image
void cacherChars(PPMImage *img, unsigned char c[],int filtre[TAILEFILTRE])
{
	//On recupere la taille de la chaine de chararactere
	int stringLength = strlen(c);
	int tailleTabPixel = 2 * 8 * strlen(c);
	//Tableau recuperant les n pixels les plus lourd
	long *tabPixels = malloc(tailleTabPixel * sizeof(long));
	//On initialise le tableau à 0
	for (int i = 0; i != tailleTabPixel; i++)
	{
		tabPixels[i] = 0;
	}
	
	//Rebord
	int rebord = 20;
	int dimFiltre = (int)sqrt(TAILEFILTRE);

	int i;
	if (img) {
		//Pour chaque pixel ne se trouvant pas sur les bord 
		for (i = (rebord)*img->x ; i < (img->x*img->y) - (rebord*img->x) ; i++) {
			if (i % (img->x) != 0 && i % (img->x) != ((img->x) - (rebord + 1))) {
				long tab[2];
				tab[0] = i;
				tab[1] = 0;
				//On applique le filtre passé en parametre pour calculer le <<poids>> du pixel
				int indiceFiltre = 0;
				for (int b = (-dimFiltre/2); b != (dimFiltre/2)+1 ; b++) {
					for (int y = (-dimFiltre / 2); y != (dimFiltre / 2) + 1 ; y++) {
						int numeroPixel = i + (b * img->x) + y;
						tab[1] += filtre[indiceFiltre] * (img->data[numeroPixel].red + img->data[numeroPixel].green);
						//Verification calculs : 
						//printf("b =  %d    I = %d   Indice : %d Pixel : %d \n",b,i,indiceFiltre,numeroPixel);
						indiceFiltre++;
					}
				}
				//printf("\n\n");
				//Si le pixel courant fait partie des 8 plus lourds pixels alors on l'ajoute dans la liste trié des plus lourds pixels
				rangerPixelDansTab(tabPixels,tab, tailleTabPixel);
			}
			else
			{
				i += rebord;
			}
		}
		
	}

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
				if (img->data[tabPixels[(i*2)+(y*8 * 2)]].blue % 2 == 0)
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

//Trouve les characteres cachés dans l'image à l'aide du filtre associé
void trouverChars(PPMImage *img, int nbChar,int filtre[TAILEFILTRE])
{
	
	int tailleTabPixel = 2 * 8 * nbChar;
	//Ce tableau contient les n valeurs les plus lourdes ainsi que leur position coresspondante dans l'image
	long *tabPixels = malloc(tailleTabPixel * sizeof(long));
	//On initialise le tableau à 0
	for (int i = 0; i != tailleTabPixel; i++)
	{
		tabPixels[i] = 0;
	}

	//Attention que le rebord ne soit pas trop petit par rapport à la dimension du filtre
	int rebord = 5;
	int dimFiltre = (int)sqrt(TAILEFILTRE);
	int i;
	if (img) {
		//Poour chaque pixel ne se trouvant pas sur les bord 
		for (i = (rebord)*img->x; i < (img->x*img->y) - (rebord*img->x); i++) {
			if (i % (img->x) != 0 && i % (img->x) != ((img->x) - (rebord + 1))) {
				long tab[2];
				tab[0] = i;
				tab[1] = 0;
				//On applique le filtre passé en parametre pour calculer le <<poids>> du pixel
				int indiceFiltre = 0;
				for (int b = (-dimFiltre / 2); b != (dimFiltre / 2) + 1; b++) {
					for (int y = (-dimFiltre / 2); y != (dimFiltre / 2) + 1; y++) {
						int numeroPixel = i + (b * img->x) + y;
						tab[1] += filtre[indiceFiltre] * (img->data[numeroPixel].red + img->data[numeroPixel].green);
						//printf("b =  %d    y = %d   Indice : %d Pixel : %d \n",b,y,indiceFiltre,numeroPixel);
						indiceFiltre++;
					}
				}
				//Si le pixel courant fait partie des 8 plus lourds pixels alors on l'ajoute dans la liste trié des plus lourds pixels
				rangerPixelDansTab(tabPixels, tab, tailleTabPixel);
			}
			else
			{
				i += rebord;
			}
		}
	}

	for (int y = 0; y != nbChar; y++)
	{
		//Pour chaque octet
		unsigned char* dest = malloc(8);
		for (int i = 0; i != 8 ; i++)
		{
			//Si le bit de poids faible de la couleur bleu est 0
			if (img->data[tabPixels[(i*2) + (y * 8 * 2)]].blue % 2 == 0)
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

	PPMImage *image;
	//Filtre à utiliser, le filtre peut avoir différentes tailles 9,25,49,81....
	int filtre[TAILEFILTRE] = {1,2,2,1,2,1,2,1,1,2,2,2,1,2,2,2,1,2,2,1,2,2,2,1,1 };
	//Characteres à cacher
	unsigned char c[] = "Bonjour Monde" ;
	image = readPPM("images/gare.ppm");
	printf("Largeur %d, Hauteur %d \n", image->x, image->y);
	//On cache le charactere dans l'image à l'aide du filtre
	cacherChars(image, c, filtre);
	//On cherche les charactere caché grace au filtre
	trouverChars(image, 13, filtre);
	
	return 0;
}

