M = 64
K = 32
N = 60

# matrix sizes in the memory
# elements of a take sizeof(int8) = 1 byte
# elements of b - sizeof(int16) = 2 bytes
# elements of c - sizeof(int32) = 4 bytes
size_a = M * K * 1
size_b = K * N * 2
size_c = M * N * 4

# determining the sequence of memory addresses that we access in the function
mem_access_stack = list()

pa = 0    # a data begins right at the 0 address
pc = size_a + size_b    # c data begins right after all a and b data 

for y in range(M):
    
    for x in range(N):
        
        pb = size_a    # b data begins right after all a data 
        
        for k in range(K):
            
            # accessing pa[k] = [pa + k]
            mem_access_stack.append(pa + 1 * k)
            
            # accessing pb[x] = [pb + 2x, pb + 2x + 1]
            for i in range(2):
                mem_access_stack.append(pb + 2 * x + i)
            
            pb += 2 * N    # moving pb pointer to N sets of 2 bytes
            
        # accessing pc[x] = [pc + 4x, ..., pc + 4x + 3]
        for i in range(4):
            mem_access_stack.append(pc + 4 * x + i)
        
    pa += K * 1    # moving pa pointer to K sets of 1 byte
    pc += N * 4    # moving pc pointer to N sets of 4 bytes
    
    
# =============================================================================
    
    
# modeling cache system 
# we will remember the state of cache line (valid, dirty), 
# but won't fetch and store the data itself

# parsing memory adress
def parse_address(x):
    # x = [b_18 : b_0]
    tag = x >> 9    # [b_18 : b_9]
    index = (x >> 4) % 32    # [b_8 : b_4]
    offset = x % 16    # [b_3 : b_0]
    return tag, index, offset

# cache consists of 32 sets of two cache lines
# cache[x][i] - i-th cahce line of x-th set in format [valid, dirty, tag]
cache = [[[False, False, None], [False, False, None]] for i in range(32)]


# returns True if data of xth adress is in cache
# fetches data of xth address to cache and returns False otherwise
import copy
def get_x(x):
    tag, index, offset = parse_address(x)
    for i in range(2):
        if cache[index][i][0] == True and cache[index][i][2] == tag:
            return True
    # if xth adress line is not in cache, 
    # we need to fetch it to cache[index][0]
    # and replace cache[index][1] with previous value 
    # of cache[index][0], if it was valid
    if cache[index][0][0] == False:
        cache[index][0] = [True, False, tag]
    else:
        cache[index][1] = copy.deepcopy(cache[index][0])
        cache[index][0] = [True, False, tag]
    return False
   
# any time we access some address in memory, we first search it in cache
# here we model the cache and count the number of hits to the cache
hits = 0
total = len(mem_access_stack)
for x in mem_access_stack:
    if get_x(x):
        hits += 1

print("hits rate: {:.2%}".format(hits/total))

    
# =============================================================================


# returns time needed to read the data of xth adress line is in cache
def get_time_read_x(x):
    tag, index, offset = parse_address(x)
    # number of bytes we are reading (1 for matrix a, 2 for b, 4 for c)
    responce_time = 0
    if x < size_a:
        responce_time = 1
    elif x < size_a + size_b:
        responce_time = 2
    else:
        responce_time = 4
    
    for i in range(2):
        if cache[index][i][0] == True and cache[index][i][2] == tag:
            # if x is in cahce, we immedeatly return the value
            return 6 + responce_time
        
    # if xth adress line is not in cache,
    # we need to fetch it to cache[index][0]
    
    # in case cache[index][0] is not valid, we'll write x there
    if cache[index][0][0] == False:
        cache[index][0] = [True, False, tag]
        return 4 + 100 + responce_time 
        # 4 for searching in cahce and 100 for fetching from memory
    
    # otherwise if cache[index][0] is valid,
    # we'll replace cahce[index][1] with it
    else:
        res_time = 4 + 100 + responce_time
        # 4 for searching in cahce and 100 for fetching from memory
        
        # if cahce[index][1] is valid and dirty, 
        # we need to push it to memory
        if cache[index][1][0] == True and cache[index][1][1] == True:
            res_time += 100    # moving cache[index][1] to memoty
            
        cache[index][1] = copy.deepcopy(cache[index][0])
        cache[index][0] = [True, False, tag]
        return res_time
    
    
    
# returns time needed to read the data of xth adress line is in cache    
def get_time_write_x(x):
    tag, index, offset = parse_address(x)
    # number of bytes we are writing (1 for matrix a, 2 for b, 4 for c)
    responce_time = 0
    if x < size_a:
        responce_time = 1
    elif x < size_a + size_b:
        responce_time = 2
    else:
        responce_time = 4    
    for i in range(2):
        if cache[index][i][0] == True and cache[index][i][2] == tag:
            cache[index][i][1] = True
            # if x is in cahce, 
            # we replace it with new value and mark as dirty
            return 6 + responce_time
        
    # otherwise we need to fetch x to cache first, and then replace it,
    # but we shouldn't add 6 clock tics to result
    res_time = get_time_read_x(x)
    get_time_write_x(x)    # marking as dirty
    return res_time + responce_time

res_clk = 0

# adding all time to access the memory/cache
for x in mem_access_stack:
    if x < size_a + size_b:
        # accessing a or b to read data
        res_clk += get_time_read_x(x)
    else:
        # accessing c to write data
        res_clk += get_time_write_x(x)
    
print("memory access time:", res_clk)
    
res_clk += 2    # initialize pa, pc
for y in range(M):
    res_clk += 3    # new loop iteration, y += 1 (add & assign)
    for x in range(N):
        res_clk += 1    # new loop iteration
        res_clk += 2    # initialize pb, s
        for k in range(K):
            res_clk += 6    
            # multiplication and addition in s += pa[k] * pb[x]
            res_clk += 1    # addition in pb += N
    res_clk += 2    # addition in pa += K, pc += N
        
res_clk += 1 # exit function

print("total time:", res_clk)


# =============================================================================


def print_cache():
    for i in range(32):
        print("Set ", i, ":", sep='')
        print(cache[i][0])
        print(cache[i][1])
        print()
        
