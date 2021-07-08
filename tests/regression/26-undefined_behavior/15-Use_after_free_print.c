// PARAM:  --sets ana.spec.file useafterfree.spec --set ana.activated[+] "'spec'" --enable dbg.debug --disable warn.debug
#include<stdio.h>
#include<stdlib.h>

int main() {
  int* a = malloc(10*sizeof(int));
  for(int i = 0; i < 10; i++) {
    a[i] = 0xff;
  }

  free(a);

  for(int i = 0; i < 10; i++) {
    printf("%d ", a[i]); // print is handled differently. Should also warn in the future
  }
  printf("\n");
  return 0;
}
