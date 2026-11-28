import sys, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from scipy.optimize import minimize
d = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(float)/255
m = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(float)/255
lin = lambda c: np.where(c<=0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
srgb = lambda c: np.where(c<=0.0031308, c*12.92, 1.055*np.clip(c,0,1)**(1/2.4)-0.055)
ox, oy = 22, 42
regions = {'content': (300, 520, 950, 650), 'sidebar': (20, 420, 230, 640)}
for name,(x0,y0,x1,y1) in regions.items():
    tgt = m[oy+y0:oy+y1, ox+x0:ox+x1]
    pad = 120
    X0, Y0 = max(ox+x0-pad,0), max(oy+y0-pad,0)
    sub = d[Y0:oy+y1+pad:2, X0:ox+x1+pad:2]
    tgt = m[oy+y0:oy+y1:2, ox+x0:ox+x1:2]
    sy, sx = (oy+y0-Y0)//2, (ox+x0-X0)//2
    def model(p, ret=False):
        sigma, k, sat, lift = p
        b = np.stack([gaussian_filter(sub[...,c], abs(sigma)/2) for c in range(3)], -1)
        L = lin(b)
        g = (L*[0.2126,0.7152,0.0722]).sum(-1, keepdims=True)
        out = srgb((g + (L-g)*sat)*k) + lift
        out = out[sy:sy+tgt.shape[0], sx:sx+tgt.shape[1]]
        return out if ret else ((out-tgt)**2).mean()
    best = None
    for s0 in (8, 16, 30, 50):
        r = minimize(model, [s0, 0.5, 1.2, 0.0], method='Nelder-Mead', options={'maxiter': 200, 'xatol':1e-3,'fatol':1e-7})
        if best is None or r.fun < best.fun: best = r
    print(name, 'sigma=%.1f k=%.3f sat=%.2f lift=%.3f rmse=%.4f' % (*best.x, best.fun**0.5))
