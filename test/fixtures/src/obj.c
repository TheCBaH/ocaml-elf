/* Relocatable fixture: a global, a local function, data with a pointer (needs a relocation),
   zero-filled data and a call to an undefined function. */
extern int ext(int);

int counter = 3;
int table[16];
const char msg[] = "elf fixture";
int *counter_ref = &counter;

static int local_fn(int x) { return x + 1; }

int gfn(int x) { return local_fn(x) + counter; }
int call_ext(int x) { return ext(x) + table[2]; }
