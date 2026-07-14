import sys, struct
sys.path.insert(0,'/tmp')
import appearances_pb2
DAT="/mnt/c/Users/Mateus/Desktop/crystal/gameclient-main/assets/appearances-6adb790d1064c2d31ffb2e5ce1a7aef376942ba672edea2adb6cafc620dd18f1.dat"
apps=appearances_pb2.Appearances(); apps.ParseFromString(open(DAT,'rb').read())
byid={o.id:o for o in apps.object if o.HasField('id')}
UNK,OUT,CRE=0x61,0x62,0x63
data=bytes.fromhex(open('/tmp/pktmap2.hex').read().strip())
p=[1747]  # right after 0x64 + pos (z=15 login map)
def u8(): v=data[p[0]];p[0]+=1;return v
def u16(): v=struct.unpack_from('<H',data,p[0])[0];p[0]+=2;return v
def u32(): v=struct.unpack_from('<I',data,p[0])[0];p[0]+=4;return v
def peek16(): return struct.unpack_from('<H',data,p[0])[0] if p[0]+2<=len(data) else 0
def st(): n=u16();v=data[p[0]:p[0]+n];p[0]+=n;return v.decode('latin1')
def getOutfit():
    lt=u16()
    if lt!=0: u8();u8();u8();u8();u8()
    else: u16()
    m=u16()
    if m!=0: u8();u8();u8();u8()
def getCreature(idt):
    known=(idt==OUT)
    if idt==OUT: u32()
    elif idt==UNK:
        u32();u32();ct=u8()
        if ct==3:u32()
        st()
    elif idt==CRE:
        u32();u8();u8();return
    u8();u8();getOutfit();u8();u8();u16()
    ic=u8()
    for i in range(ic):u8();u8();u16()
    u8();u8()
    if not known:u8()
    ct2=u8()
    if ct2==3:u32()
    if ct2==0:u8()
    u8();u8();u8();u8()
def getItemThings():
    # read one occupied tile's things; stop at marker (don't consume)
    n=0
    while n<256:
        if peek16()>=0xff00: return
        p0=p[0];iid=u16()
        if iid==0: raise ValueError(f'id0@{p0}')
        if iid in (UNK,OUT,CRE): getCreature(iid); n+=1; continue
        fl=byid.get(iid)
        if fl:
            f=fl.flags
            if f.cumulative or f.liquidpool or f.liquidcontainer:u8()
            if f.container:
                ct=u8()
                if ct==2:p[0]+=4
                elif ct==9:p[0]+=8
                elif ct==11:p[0]+=12
            if f.show_off_socket:
                lt=u16()
                if lt!=0:u8();u8();u8();u8();u8()
                else:u16()
                lm=u16()
                if lm!=0:u8();u8();u8();u8()
                u8();u8()
            if (f.HasField('upgradeclassification') and f.upgradeclassification.upgrade_classification>0):u8()
            if f.expire or f.expirestop or f.clockexpire:p[0]+=5
            if f.wearout:p[0]+=5
            if f.wrapkit:p[0]+=2
        n+=1

# Simulate the SERVER's GetFloorDescription read-side: walk slots, but driven by the
# wire tokens. We reconstruct skipIn/skipOut per floor exactly like the server would,
# by tracking a shared skip across floors as the wire is consumed.
# Server model: per slot, if tile -> (flush if skip>=0) + tile, skip=0. if empty: ++skip
#   (or 0xFE flush). We read tokens: a tile token = occupied slot; a [N][0xFF] marker we
#   must MAP back to how many empty slots it represents given the server's skip state.
# Easier: replay the server algorithm but ask "is this slot a tile?" by peeking the wire.
# A slot is a tile iff, at the point the server would emit it, the next wire token is a
# tile (after consuming the pending flush marker). This is circular, so instead we just
# count: consume tokens, marker [N] => N empty slots were emitted as one flush AND it is
# preceded by 'skip' that the server reset. We reconstruct slot counts.

floors = [13,14,15]
W,H=18,14
# Replay: skip starts -1, shared. For each floor, iterate W*H slots. At each slot decide
# tile vs empty by simulating server given the wire. But the wire only has tiles+markers.
# Key realization: marker [N][0xFF] on the wire == the server flushing N pending empties
# that occurred BEFORE the upcoming tile. So reading order is: [marker(=prev empties)] tile.
# So: maintain pending=0. Read token:
#   marker N: these are N empty slots (already passed). emit them. (also 0xFFFF=256 reset)
#   tile: 1 occupied slot.
# Count slots per floor with carry.
skip_state = -1
slot_global = 0
floor_idx = 0
floor_slots = 0
per_floor = []
def flush_record():
    global floor_slots, floor_idx
    per_floor.append((floors[floor_idx], floor_slots))

total_per_floor = W*H
fcount=[0]*3
ftiles=[0]*3
cur=0  # current floor index
filled=0  # slots filled in current floor
try:
    # We emulate by reading tokens and distributing slots across floors in order.
    while cur < 3:
        if peek16()>=0xff00:
            m=u16(); n=(256 if m==0xffff else (m&0xff))
            # n empty slots
            while n>0 and cur<3:
                take=min(n, total_per_floor-filled)
                fcount[cur]+=take; filled+=take; n-=take
                if filled==total_per_floor:
                    cur+=1; filled=0
            continue
        # tile
        getItemThings()
        if cur<3:
            ftiles[cur]+=1; fcount[cur]+=1; filled+=1
            if filled==total_per_floor:
                cur+=1; filled=0
    print('Reconstructed per-floor (token-driven):')
    for i,z in enumerate(floors):
        print(f'  z={z}: slots-accounted={fcount[i]} tiles={ftiles[i]}')
    print(f'ended @ {p[0]}, next bytes: {data[p[0]:p[0]+6].hex()}')
except Exception as e:
    print(f'err: {e} @ {p[0]}; floors so far: {list(zip(floors,fcount,ftiles))}; filled={filled} cur={cur}')
    print(f'ctx: {data[max(0,p[0]-6):p[0]+10].hex()}')
