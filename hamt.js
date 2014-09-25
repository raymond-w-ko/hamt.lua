define(["require", "exports"], (function (require, exports) {
    "use strict";
    var hash, empty, tryGetHash, tryGet, getHash, get, hasHash, has, setHash, set, modifyHash, modify,
        removeHash, remove, fold, count, pairs, keys, values, BUCKET_SIZE = Math.pow(2, 5),
        mask = (BUCKET_SIZE - 1),
        MAX_INDEX_NODE = (BUCKET_SIZE / 2),
        MIN_ARRAY_NODE = (BUCKET_SIZE / 4),
        nothing = ({}),
        popcount = (function (x) {
            var x0 = (x - ((x >> 1) & 1431655765)),
                x1 = ((x0 & 858993459) + ((x0 >> 2) & 858993459)),
                x2 = ((x1 + (x1 >> 4)) & 252645135),
                x3 = (x2 + (x2 >> 8)),
                x4 = (x3 + (x3 >> 16));
            return (x4 & 127);
        }),
        arrayUpdate = (function (at, v, arr) {
            var out = arr.slice();
            (out[at] = v);
            return out;
        }),
        arraySpliceOut = (function (at, arr) {
            var out = arr.slice();
            out.splice(at, 1);
            return out;
        }),
        arraySpliceIn = (function (at, v, arr) {
            var out = arr.slice();
            out.splice(at, 0, v);
            return out;
        });
    (hash = (function (str) {
        if (((typeof str) === "number")) return str;
        var hash0 = 0;
        for (var i = 0, len = str.length;
            (i < len);
            (i = (i + 1))) {
            var c = str.charCodeAt(i);
            (hash0 = ((((hash0 << 5) - hash0) + c) | 0));
        }
        return hash0;
    }));
    (empty = null);
    var Leaf = (function (hash0, key, value) {
            var self = this;
            (self.hash = hash0);
            (self.key = key);
            (self.value = value);
        }),
        Collision = (function (hash0, children) {
            var self = this;
            (self.hash = hash0);
            (self.children = children);
        }),
        IndexedNode = (function (mask0, children) {
            var self = this;
            (self.mask = mask0);
            (self.children = children);
        }),
        ArrayNode = (function (count, children) {
            var self = this;
            (self.count = count);
            (self.children = children);
        }),
        isLeaf = (function (node) {
            return (((node === null) || (node instanceof Leaf)) || (node instanceof Collision));
        }),
        expand = (function (frag, child, bitmap, subNodes) {
            var bit = bitmap,
                arr = [],
                count = 0;
            for (var i = 0; bit; i = (i + 1)) {
                if ((bit & 1)) {
                    arr[i] = subNodes[count];
                    count = (count + 1);
                }
                bit = (bit >>> 1);
            }
            arr[frag] = child;
            return new(ArrayNode)(count + 1, arr);
        }),
        pack = (function (removed, elements) {
            var children = [],
                bitmap = 0;
            for (var i = 0, len = elements.length; (i < len); (i = (i + 1))) {
                var elem = elements[i];
                if (((i !== removed) && (!(!elem)))) {
                    children.push(elem);
                    bitmap = (bitmap | (1 << i));
                }
            }
            return new(IndexedNode)(bitmap, children);
        }),
        mergeLeaves = (function (shift, n1, n2) {
            var h1 = n1.hash,
                h2 = n2.hash,
                subH1, subH2;
            if (h1 === h2) {
                return new(Collision)(h1, [n2, n1])
            } else {
                subH1 = (h1 >>> shift) & mask;
                subH2 = (h2 >>> shift) & mask;
                var bitmap = (1 << subH1) | (1 << subH2);
                var children;
                if (subH1 === subH2) {
                    children = [mergeLeaves((shift + 5), n1, n2)];
                } else {
                    children = (subH1 < subH2) ? [n1, n2] : [n2, n1];
                }
                return new(IndexedNode)(bitmap, children);
            }
        }),
        updateCollisionList = (function (h, list, f, k) {
            var target, i = 0;
            for (var len = list.length; (i < len); (i = (i + 1))) {
                var child = list[i];
                if (child.key === k) {
                    (target = child);
                    break;
                }
            }
            var v = target ? f(target.value) : f();
            if (nothing === v) {
                return arraySpliceOut(i, list)
            } else {
                return arrayUpdate(i, new(Leaf)(h, k, v), list);
            }
        }),
        lookup;
    (Leaf.prototype.lookup = (function (_, _0, k) {
        var self = this;
        return ((k === self.key) ? self.value : nothing);
    }));
    (Collision.prototype.lookup = (function (_, h, k) {
        var self = this;
        if (h === self.hash) {
            for (var i = 0, len = self.children.length; (i < len); i = i + 1) {
                var child = self.children[i];
                if (k === child.key)
                    return child.value;
            }
        }
        return nothing;
    }));
    (IndexedNode.prototype.lookup = (function (shift, h, k) {
        var self = this,
            frag = ((h >>> shift) & mask),
            bit = (1 << frag);
        if (self.mask & bit) {
            var n = self.children[popcount(self.mask & (bit - 1))];
            return lookup(n, (shift + 5), h, k)
        } else {
            return nothing;
        }
    }));
    (ArrayNode.prototype.lookup = (function (shift, h, k) {
        var self = this,
            frag = ((h >>> shift) & mask),
            child = self.children[frag];
        return lookup(child, (shift + 5), h, k);
    }));
    (lookup = (function (n, shift, h, k) {
        return ((!n) ? nothing : n.lookup(shift, h, k));
    }));
    var alter;
    (Leaf.prototype.modify = (function (shift, f, h, k) {
        var v, v0, self = this;
        if (k === self.key) {
          v = f(self.value);
          return (nothing === v) ? null : new(Leaf)(h, k, v);
        } else {
          v0 = f();
          return (nothing === v0) ? self : mergeLeaves(shift, self, new(Leaf)(h, k, v0));
        }
    }));
    (Collision.prototype.modify = (function (shift, f, h, k) {
        var self = this,
            list = updateCollisionList(self.hash, self.children, f, k);
        if (list.length > 1) {
            return new(Collision)(self.hash, list)
        } else {
            return list[0];
        }
    }));
    (IndexedNode.prototype.modify = (function (shift, f, h, k) {
        var self = this;
        var mask0 = self["mask"];
        var children = self["children"];
        var frag = ((h >>> shift) & mask);
        var bit = (1 << frag);
        var indx = popcount((mask0 & (bit - 1)));
        var exists = (mask0 & bit);
        var child = alter((exists ? children[indx] : null), (shift + 5), f, h, k);
        var removed = exists && (!child);
        var added = (!exists) && (!(!child));

        var bitmap0 =
            removed ? (mask0 & (~bit)) :
            (added ? (mask0 | bit) :
             mask0);
        if (!bitmap0) {
            return null;
        } else {
            return
                removed ?
                    ((children.length <= 2) && isLeaf(children[(indx ^ 1)])) ?
                         children[(indx ^ 1)] :
                         new(IndexedNode)(bitmap0, arraySpliceOut(indx, children))
                :
                added ?
                    (children.length >= MAX_INDEX_NODE) ?
                        expand(frag, child, mask0, children) :
                        new(IndexedNode)(bitmap0, arraySpliceIn(indx, child, children))
                : new(IndexedNode)(bitmap0, arrayUpdate(indx, child, children));
        }
    }));
    (ArrayNode.prototype.modify = (function (shift, f, h, k) {
        var self = this;
        var count = self["count"];
        var children = self["children"];
        var frag = ((h >>> shift) & mask);
        var child = children[frag];
        var newChild = alter(child, (shift + 5), f, h, k);
        if ((!child) && (!(!newChild))) {
            return new(ArrayNode)((count + 1), arrayUpdate(frag, newChild, children));
        } else if ((!(!child)) && (!newChild)) {
            return ((count - 1) <= MIN_ARRAY_NODE) ?
                pack( frag, children) :
                new(ArrayNode)((count - 1), arrayUpdate(frag, null, children))
        } else {
            return new(ArrayNode)(count, arrayUpdate(frag, newChild, children));
        }
    }));
    (alter = (function (n, shift, f, h, k) {
        var v;
        return
            (!n) ?
                ((v = f()), ((nothing === v) ?
                    null :
                    new(Leaf)(h, k, v)))
                : n.modify(shift, f, h, k);
    }));
    (tryGetHash = (function (alt, h, k, m) {
        var val = (!m) ? nothing : m.lookup(0, h, k);
        return ((nothing === val) ? alt : val);
    }));
    (tryGet = (function (alt, k, m) {
        var h = hash(k);
        var val = (!m) ? nothing : m.lookup(0, h, k);
        return ((nothing === val) ? alt : val);
    }));
    (getHash = (function (h, k, m) {
        var val = ((!m) ? nothing : m.lookup(0, h, k));
        return ((nothing === val) ? null : val);
    }));
    (get = (function (k, m) {
        var h = hash(k);
        var val = (!m) ? nothing : m.lookup(0, h, k);
        return ((nothing === val) ? null : val);
    }));
    (hasHash = (function (h, k, m) {
        var y;
        y = (!m) ? nothing : m.lookup(0, h, k);
        return !(nothing === y);
    }));
    (has = (function (k, m) {
        var h = hash(k);
        var y;
        y = (!m) ? nothing : m.lookup(0, h, k);
        return !(nothing === y);
    }));
    (modifyHash = (function (h, k, f, m) {
        var v;
        return (!m) ?
            ((v = f()), ((nothing === v) ?
                null :
                new(Leaf)(h, k, v))) :
            m.modify(0, f, h, k);
    }));
    (modify = (function (k, f, m) {
        var h = hash(k);
        var v;
        return
            (!m) ?
                ((v = f()), ((nothing === v) ?
                    null :
                    new(Leaf)(h, k, v))) :
                m.modify(0, f, h, k);
    }));
    (setHash = (function (h, k, v, m) {
        var f = (function () {
            return v;
        });
        return (!m) ?
            ((nothing === v) ?
                null :
                new(Leaf)(h, k, v)) :
            m.modify(0, f, h, k);
    }));
    (set = (function (k, v, m) {
        var h = hash(k),
            f = (function () {
                return v;
            });
        return ((!m) ?
                ((nothing === v) ?
                     null :
                     new(Leaf)(h, k, v)) :
                m.modify(0, f, h, k));
    }));
    var del = (function () {
        return nothing;
    });
    (removeHash = (function (h, k, m) {
        return ((!m) ? ((nothing === nothing) ? null : new(Leaf)(h, k, nothing)) : m.modify(0, del, h,
            k));
    }));
    (remove = (function (k, m) {
        return removeHash(hash(k), k, m);
    }));
    (Leaf.prototype.fold = (function (f, z) {
        var self = this;
        return f(z, self);
    }));
    (Collision.prototype.fold = (function (f, z) {
        var __o = this,
            children = __o["children"];
        return children.reduce(f, z);
    }));
    (IndexedNode.prototype.fold = (function (f, z) {
        var __o = this,
            children = __o["children"],
            z1 = z;
        for (var i = 0, len = children.length;
            (i < len);
            (i = (i + 1))) {
            var c = children[i];
            (z1 = ((c instanceof Leaf) ? f(z1, c) : c.fold(f, z1)));
        }
        return z1;
    }));
    (ArrayNode.prototype.fold = (function (f, z) {
        var __o = this,
            children = __o["children"],
            z1 = z;
        for (var i = 0, len = children.length;
            (i < len);
            (i = (i + 1))) {
            var c = children[i];
            if (c) {
                (z1 = ((c instanceof Leaf) ? f(z1, c) : c.fold(f, z1)));
            }
        }
        return z1;
    }));
    (fold = (function (f, z, m) {
        return ((!m) ? z : m.fold(f, z));
    }));
    var f = (function (y) {
        return (1 + y);
    });
    (count = (function (m) {
        return ((!m) ? 0 : m.fold(f, 0));
    }));
    var build = (function (p, __o) {
        var key = __o["key"],
            value = __o["value"];
        p.push([key, value]);
        return p;
    });
    (pairs = (function (m) {
        var z = [];
        return ((!m) ? z : m.fold(build, z));
    }));
    var build0 = (function (p, __o) {
        var key = __o["key"];
        p.push(key);
        return p;
    });
    (keys = (function (m) {
        var z = [];
        return ((!m) ? z : m.fold(build0, z));
    }));
    var build1 = (function (p, __o) {
        var value = __o["value"];
        p.push(value);
        return p;
    });
    (values = (function (m) {
        var z = [];
        return ((!m) ? z : m.fold(build1, z));
    }));
    (exports["hash"] = hash);
    (exports["empty"] = empty);
    (exports["tryGetHash"] = tryGetHash);
    (exports["tryGet"] = tryGet);
    (exports["getHash"] = getHash);
    (exports["get"] = get);
    (exports["hasHash"] = hasHash);
    (exports["has"] = has);
    (exports["setHash"] = setHash);
    (exports["set"] = set);
    (exports["modifyHash"] = modifyHash);
    (exports["modify"] = modify);
    (exports["removeHash"] = removeHash);
    (exports["remove"] = remove);
    (exports["fold"] = fold);
    (exports["count"] = count);
    (exports["pairs"] = pairs);
    (exports["keys"] = keys);
    (exports["values"] = values);
}));
