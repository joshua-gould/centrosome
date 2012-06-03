import numpy as np
cimport numpy as np
ctypedef np.int32_t DTYPE_t  # 32-bit pixel positions and labels

# Does the path a->b->c form a convexity in the plane?
cdef inline int CONVEX(int a_i, int a_j,
                       int b_i, int b_j,
                       int c_i, int c_j) nogil:
    cdef int ab_i, ab_j, bc_i, bc_j
    ab_i = b_i - a_i
    ab_j = b_j - a_j
    bc_i = c_i - b_i
    bc_j = c_j - b_j
    # note that x is j, y is i
    return (ab_j * bc_i - bc_j * ab_i) > 0

def convex_hull_ijv(in_labels_ijv,
                    indexes_in):
    # reorder by v, then j, then i.  Note: we will overwrite this array with
    # the output.  The sorting allocates a new copy, and it's guaranteed to be
    # large enough for the convex hulls.
    cdef np.ndarray[DTYPE_t, ndim=2] labels_ijv = in_labels_ijv.astype(np.int32)[np.lexsort(in_labels_ijv.T), :]
    cdef np.ndarray[DTYPE_t, ndim=1] indexes = np.asarray(indexes_in, np.int32).ravel()
    # declaration of local variables
    cdef int num_indexes, max_i, max_j, max_label, pixidx, outidx, cur_req, cur_label
    cdef int num_vertices, start_j, cur_pix_i, cur_pix_j, end_j, need_last_upper_point
    cdef int num_emitted
    # an indirect sorting array for indexes
    cdef np.ndarray[DTYPE_t, ndim=1] indexes_reorder = np.argsort(indexes).astype(np.int32)
    num_indexes = len(indexes)
    # find the maximums
    max_i, max_j, max_label = labels_ijv.max(axis=0)
    # allocate the upper and lower vertex buffers, and initialize them to extreme values
    cdef np.ndarray[DTYPE_t, ndim=1] upper = np.empty(max_j + 1, np.int32)
    cdef np.ndarray[DTYPE_t, ndim=1] lower = np.empty(max_j + 1, np.int32)
    cdef np.ndarray[DTYPE_t, ndim=1] vertex_counts = np.zeros(num_indexes, np.int32)
    cdef np.ndarray[DTYPE_t, ndim=1] hull_offsets = np.zeros(num_indexes, np.int32)
    # initialize them to extreme values
    upper[:] = -1
    lower[:] = max_i + 1
    pixidx = 0  # the next input pixel we'll process
    outidx = 0  # the next row to be written in the output
    for cur_req in range(num_indexes):
        cur_label = indexes[indexes_reorder[cur_req]]
        while (cur_label <= max_label) and (labels_ijv[pixidx, 2] < cur_label):
            pixidx += 1
            if pixidx == labels_ijv.shape[0]:
                break
        num_vertices = 0
        hull_offsets[cur_req] = outidx
        if (pixidx == labels_ijv.shape[0]) or (cur_label != labels_ijv[pixidx, 2]):
            # cur_label's hull will have 0 points
            continue
        start_j = labels_ijv[pixidx, 1]
        while cur_label == labels_ijv[pixidx, 2]:
            cur_pix_i, cur_pix_j = labels_ijv[pixidx, :2]
            if upper[cur_pix_j] < cur_pix_i:
                upper[cur_pix_j] = cur_pix_i
            if lower[cur_pix_j] > cur_pix_i:
                lower[cur_pix_j] = cur_pix_i
            pixidx += 1
            if pixidx == labels_ijv.shape[0]:
                break
        end_j = labels_ijv[pixidx - 1, 1]
        print "STARTJ/END_J", start_j, end_j
        print "LOWER", lower[start_j:end_j + 1]
        print "UPPER", upper[start_j:end_j + 1]
        # At this point, the upper and lower buffers have the extreme high/low
        # points, so we just need to convexify them.  We have copied them out
        # of the labels_ijv array, so we write out the hull into that array
        # (via its alias "out").  We are careful about memory when we do so, to
        # make sure we don't invalidate the next entry in labels_ijv.
        #
        # We assume that the j-coordinates are dense.  If this assumption is
        # violated, we should re-walk the pixidx values we just copied to only
        # deal with columns that actually have points.
        #
        # Produce hull in counter-clockwise order, starting with lower
        # envelope.  Reset the envelopes as we do so.

        # Macro-type functions from Python version
        # def CONVEX(pt_i, pt_j, nemitted):
        #     # We're walking CCW, so left turns are convex
        #     d_i_prev, d_j_prev, z = out[out_base_idx + nemitted - 1, :] - out[out_base_idx + nemitted - 2, :]
        #     d_i_cur = pt_i - out[out_base_idx + nemitted - 1, 0]
        #     d_j_cur = pt_j - out[out_base_idx + nemitted - 1, 1]
        #     # note that x is j, y is i
        #     return (d_j_prev * d_i_cur - d_j_cur * d_i_prev) > 0
        # 
        # def EMIT(pt_i, pt_j, nemitted):
        #     while (nemitted >= 2) and not CONVEX(pt_i, pt_j, nemitted):
        #         # The point we emitted just before this one created a
        #         # concavity (or is co-linear).  Prune it.
        #         #XXX print "BACKUP"
        #         nemitted -= 1
        #     # The point is convex or we haven't emitted enough points to check.
        #     #XXX print "writing point", nemitted, pt_i, pt_j
        #     out[out_base_idx + nemitted, :] = (pt_i, pt_j, cur_label)
        #     return nemitted + 1

        need_last_upper_point = (lower[start_j] != upper[start_j])
        num_emitted = 0
        for envelope_j in range(start_j, end_j + 1):
            if lower[envelope_j] < max_i + 1:
                # MACRO EMIT(lower[envelope_j], envelope_j, num_emitted)
                while (num_emitted >= 2) and not CONVEX(labels_ijv[outidx + num_emitted - 2, 0], labels_ijv[outidx + num_emitted - 2, 1],
                                                        labels_ijv[outidx + num_emitted - 1, 0], labels_ijv[outidx + num_emitted - 1, 1],
                                                        lower[envelope_j], envelope_j):
                    # The point we emitted just before this one created a concavity (or is co-linear).  Prune it.
                    print "PRUNE"
                    num_emitted -= 1
                labels_ijv[outidx + num_emitted, :] = (lower[envelope_j], envelope_j, cur_label)
                print "ADD", (lower[envelope_j], envelope_j, cur_label)
                num_emitted += 1
                # END MACRO
                lower[envelope_j] = max_i + 1
        for envelope_j in range(end_j, start_j, -1):
            if upper[envelope_j] > -1:
                # MACRO EMIT(upper[envelope_j], envelope_j, num_emitted)
                while (num_emitted >= 2) and not CONVEX(labels_ijv[outidx + num_emitted - 2, 0], labels_ijv[outidx + num_emitted - 2, 1],
                                                        labels_ijv[outidx + num_emitted - 1, 0], labels_ijv[outidx + num_emitted - 1, 1],
                                                        lower[envelope_j], envelope_j):
                    # The point we emitted just before this one created a concavity (or is co-linear).  Prune it.
                    print "PRUNE"
                    num_emitted -= 1
                labels_ijv[outidx + num_emitted, :] = (upper[envelope_j], envelope_j, cur_label)
                print "ADD", (upper[envelope_j], envelope_j, cur_label)
                num_emitted += 1
                # END MACRO
                upper[envelope_j] = -1
        # Even if we don't add the start point, we still might need to prune.
        # MACRO EMIT(upper[start_j], envelope_j, num_emitted)
        while (num_emitted >= 2) and not CONVEX(labels_ijv[outidx + num_emitted - 2, 0], labels_ijv[outidx + num_emitted - 2, 1],
                                                        labels_ijv[outidx + num_emitted - 1, 0], labels_ijv[outidx + num_emitted - 1, 1],
                                                        lower[start_j], start_j):
            # The point we emitted just before this one created a concavity (or is co-linear).  Prune it.
            print "PRUNE"
            num_emitted -= 1
        if need_last_upper_point:
            labels_ijv[outidx + num_emitted, :] = (upper[start_j], start_j, cur_label)
            print "ADD", (upper[start_j], start_j, cur_label)
            num_emitted += 1
            # END MACRO
        upper[start_j] = -1
        # advance the output index
        vertex_counts[cur_req] = num_emitted
        outidx += num_emitted
    # reorder
    reordered = np.zeros((np.sum(vertex_counts), 3), np.int32)
    reordered_counts = np.zeros(num_indexes, np.int32)
    reordered_idx = 0
    for reordered_num in range(num_indexes):
        count = vertex_counts[indexes_reorder[reordered_num]]
        src_start = hull_offsets[indexes_reorder[reordered_num]]
        src_end = src_start + count
        dest_start = reordered_idx
        dest_end = reordered_idx + count
        reordered[dest_start:dest_end, :] = labels_ijv[src_start:src_end, :]
        reordered_idx += count
        reordered_counts[reordered_num] = count
    print "C", vertex_counts
    print "REO", reordered
    print "RC", reordered_counts
    return reordered[:, [2, 0, 1]], reordered_counts

def convex_hull(labels, indexes=None):
    """Given a labeled image, return a list of points per object ordered by
    angle from an interior point, representing the convex hull.s

    labels - the label matrix
    indexes - an array of label #s to be processed, defaults to all non-zero
              labels

    Returns a matrix and a vector. The matrix consists of one row per
    point in the convex hull. Each row has three columns, the label #,
    the i coordinate of the point and the j coordinate of the point. The
    result is organized first by label, then the points are arranged
    counter-clockwise around the perimeter.
    The vector is a vector of #s of points in the convex hull per label
    """
    if indexes == None:
        indexes = np.unique(labels)
        indexes.sort()
        indexes=indexes[indexes!=0]
    else:
        indexes=np.array(indexes)
    if len(indexes) == 0:
        return np.zeros((0,2),int),np.zeros((0,),int)
    #
    # Reduce the # of points to consider
    #
    outlines = labels
    coords = np.argwhere(outlines > 0).astype(np.int32)
    if len(coords)==0:
        # Every outline of every image is blank
        return (np.zeros((0,3),int),
                np.zeros((len(indexes),),int))

    i = coords[:,0]
    j = coords[:,1]
    labels_per_point = labels[i,j]
    pixel_labels = np.column_stack((i,j,labels_per_point))
    return convex_hull_ijv(pixel_labels, indexes)


