{-# LANGUAGE InstanceSigs  #-}
{-# LANGUAGE TupleSections #-}
module Bio.Chain.Alignment.Algorithms where

import           Control.Lens             (Index, IxValue, ix, (^?!))
import           Data.Array               (Ix (..))
import qualified Data.Array               as A (bounds, range)
import           Data.List                (maximumBy)

import           Bio.Chain
import           Bio.Chain.Alignment.Type
import           Data.Ord                 (comparing)


-- | Alignnment methods
--
newtype EditDistance e1 e2       = EditDistance        (e1 -> e2 -> Bool)
data GlobalAlignment a e1 e2     = GlobalAlignment     (Scoring e1 e2) a
data LocalAlignment a e1 e2      = LocalAlignment      (Scoring e1 e2) a
data SemiglobalAlignment a e1 e2 = SemiglobalAlignment (Scoring e1 e2) a

-- Common functions

-- | Lift simple substitution function to a ChainLike collection
--
{-# SPECIALISE substitute :: (Char -> Char -> Int) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Int #-}
{-# INLINE substitute #-}
substitute :: (Alignable m, Alignable m') => (IxValue m -> IxValue m' -> Int) -> m -> m' -> Index m -> Index m' -> Int
substitute f s t i j = f (s ^?! ix (pred i)) (t ^?! ix (pred j))

-- | Simple substitution function for edit distance
--
substituteED :: EditDistance e1 e2 -> (e1 -> e2 -> Int)
substituteED (EditDistance genericEq) x y = if x `genericEq` y then 1 else 0

-- | Default traceback stop condition.
--
{-# SPECIALISE defStop :: Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE defStop #-}
defStop :: (Alignable m, Alignable m') => Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
defStop _ s t i j = let (lowerS, _) = bounds s
                        (lowerT, _) = bounds t
                    in  i == lowerS && j == lowerT

-- | Traceback stop condition for the local alignment.
--
{-# SPECIALISE localStop :: Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE localStop #-}
localStop :: (Alignable m, Alignable m') => Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
localStop m' s t i j = let (lowerS, _) = bounds s
                           (lowerT, _) = bounds t
                       in  i == lowerS || j == lowerT || m' ! (i, j, Match) == 0

-- | Default condition of moving vertically in traceback.
--
{-# SPECIALISE defVert :: Int -> Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE defVert #-}
defVert :: (Alignable m, Alignable m') => Int -> Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
defVert gap m s t i j = (i > lowerS) && ((lowerT == j) || (m ! (pred i, j, Match) + gap == m ! (i, j, Match)))
  where
    (lowerT, _) = bounds t
    (lowerS, _) = bounds s

-- | Default condition of moving vertically in traceback with affine gap penalty.
--
{-# SPECIALISE affVert :: AffineGap -> Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE affVert #-}
affVert :: (Alignable m, Alignable m') => AffineGap -> Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
affVert AffineGap{..} m s t i j =  (i > lowerS) && ((lowerT == j) || (m ! (pred i, j, Match) + gap == m ! (i, j, Match)))
  where
    insertions  = m ! (pred i, j, Insert)
    gap | insertions == 0 = gapOpen
        | otherwise       = gapExtend
    (lowerT, _) = bounds t
    (lowerS, _) = bounds s

-- | Default condition of moving horizontally in traceback.
--
{-# SPECIALISE defHoriz :: Int -> Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE defHoriz #-}
defHoriz :: (Alignable m, Alignable m') => Int -> Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
defHoriz gap m s t i j = (j > lowerT) && ((i == lowerS) || (m ! (i, pred j, Match) + gap == m ! (i, j, Match)))
  where
    (lowerT, _) = bounds t
    (lowerS, _) = bounds s

-- | Default condition of moving horizontally in traceback with affine gap penalty.
--
{-# SPECIALISE affHoriz :: AffineGap -> Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE affHoriz #-}
affHoriz :: (Alignable m, Alignable m') => AffineGap -> Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
affHoriz AffineGap{..} m s t i j = (j > lowerT) && ((i == lowerS) || (m ! (i, pred j, Match) + gap == m ! (i, j, Match)))
  where
    deletions  = m ! (i, pred j, Delete)
    gap | deletions == 0 = gapOpen
        | otherwise      = gapExtend
    (lowerT, _) = bounds t
    (lowerS, _) = bounds s

-- | Default condition of moving diagonally in traceback.
--
{-# SPECIALISE defDiag :: (Char -> Char -> Int) -> Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> Int -> Int -> Bool #-}
{-# INLINE defDiag #-}
defDiag :: (Alignable m, Alignable m') => (IxValue m -> IxValue m' -> Int) -> Matrix m m' -> m -> m' -> Index m -> Index m' -> Bool
defDiag sub' m s t i j = let sub = substitute sub' s t
                         in  m ! (pred i, pred j, Match) + sub i j == m ! (i, j, Match)

-- | Default start condition for traceback.
--
{-# SPECIALISE defStart :: Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> (Int, Int) #-}
{-# INLINE defStart #-}
defStart :: (Alignable m, Alignable m') => Matrix m m' -> m -> m' -> (Index m, Index m')
defStart m _ _ = let ((_, _, _), (upperS, upperT, _)) = A.bounds m in (upperS, upperT)

-- | Default start condition for traceback in local alignment.
--
{-# SPECIALISE localStart :: Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> (Int, Int) #-}
{-# INLINE localStart #-}
localStart :: (Alignable m, Alignable m') => Matrix m m' -> m -> m' -> (Index m, Index m')
localStart m _ _ = let ((lowerS, lowerT, _), (upperS, upperT, _)) = A.bounds m
                       range' = A.range ((lowerS, lowerT, Match), (upperS, upperT, Match))
                   in  (\(a, b, _) -> (a, b)) $ maximumBy (comparing (m !)) range'

-- | Default start condition for traceback in semiglobal alignment.
--
{-# SPECIALISE semiStart :: Matrix (Chain Int Char) (Chain Int Char) -> Chain Int Char -> Chain Int Char -> (Int, Int) #-}
{-# INLINE semiStart #-}
semiStart :: (Alignable m, Alignable m') => Matrix m m' -> m -> m' -> (Index m, Index m')
semiStart m _ _ = let ((lowerS, lowerT, _), (upperS, upperT, _)) = A.bounds m
                      lastCol = (, upperT, Match) <$> [lowerS .. upperS]
                      lastRow = (upperS, , Match) <$> [lowerT .. upperT]
                  in  (\(a, b, _) -> (a, b)) $ maximumBy (comparing (m !)) $ lastCol ++ lastRow

-- Alignment algorithm instances

instance SequenceAlignment EditDistance where
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond ed = Conditions defStop (defDiag (substituteED ed)) (defVert 1) (defHoriz 1)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const defStart
    -- Next cell = max (d_i-1,j + 1, d_i,j-1 + 1, d_i-1,j-1 + 1 if different else 0)
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => EditDistance (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist ed mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute (substituteED ed) s t

        (lowerS, upperS) = bounds s
        (lowerT, upperT) = bounds t

        result :: Int
        result = if | i == lowerS -> index (lowerT, succ upperT) j
                    | j == lowerT -> index (lowerS, succ upperS) i
                    | otherwise -> minimum [ mat ! (pred i, pred j, k) + sub i j
                                           , mat ! (pred i,      j, k) + 1
                                           , mat ! (i,      pred j, k) + 1
                                           ]

instance SequenceAlignment (GlobalAlignment SimpleGap) where
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond (GlobalAlignment subC gap) = Conditions defStop (defDiag subC) (defVert gap) (defHoriz gap)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const defStart
    -- Next cell = max (d_i-1,j + gap, d_i,j-1 + gap, d_i-1,j-1 + s(i,j))
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => GlobalAlignment SimpleGap (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist (GlobalAlignment subC gap) mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute subC s t

        (lowerS, upperS) = bounds s
        (lowerT, upperT) = bounds t

        result :: Int
        result = if | i == lowerS -> gap * index (lowerT, succ upperT) j
                    | j == lowerT -> gap * index (lowerS, succ upperS) i
                    | otherwise -> maximum [ mat ! (pred i, pred j, k) + sub i j
                                           , mat ! (pred i,      j, k) + gap
                                           , mat ! (i,      pred j, k) + gap
                                           ]

instance SequenceAlignment (LocalAlignment SimpleGap) where
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond (LocalAlignment subC gap) = Conditions localStop (defDiag subC) (defVert gap) (defHoriz gap)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const localStart
    -- Next cell = max (d_i-1,j + gap, d_i,j-1 + gap, d_i-1,j-1 + s(i,j))
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => LocalAlignment SimpleGap (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist (LocalAlignment subC gap) mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute subC s t

        (lowerS, _) = bounds s
        (lowerT, _) = bounds t

        result :: Int
        result = if | i == lowerS -> 0
                    | j == lowerT -> 0
                    | otherwise -> maximum [ mat ! (pred i, pred j, k) + sub i j
                                           , mat ! (pred i,      j, k) + gap
                                           , mat ! (i,      pred j, k) + gap
                                           , 0
                                           ]

instance SequenceAlignment (SemiglobalAlignment SimpleGap) where
    -- The alignment is semiglobal, so we have to perform some additional operations
    {-# INLINE semi #-}
    semi = const True
    -- This is not a affine alignment, so we don't need multiple matricies
    {-# INLINE affine #-}
    affine = const False
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond (SemiglobalAlignment subC gap) = Conditions defStop (defDiag subC) (defVert gap) (defHoriz gap)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const semiStart
    -- Next cell = max (d_i-1,j + gap, d_i,j-1 + gap, d_i-1,j-1 + s(i,j))
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => SemiglobalAlignment SimpleGap (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist (SemiglobalAlignment subC gap) mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute subC s t

        (lowerS, _) = bounds s
        (lowerT, _) = bounds t

        result :: Int
        result = if | i == lowerS -> 0
                    | j == lowerT -> 0
                    | otherwise -> maximum [ mat ! (pred i, pred j, k) + sub i j
                                           , mat ! (pred i,      j, k) + gap
                                           , mat ! (i,      pred j, k) + gap
                                           ]

-------------------
  --
  --                        Affine gaps
  --
  -- There are three matrices used in all the algorithms below:
  -- 1) One stores the resulting scores for each prefix pair;
  -- 2) One stores lengths of gaps in the first sequence for each prefix pair;
  -- 3) One stores lengths of gaps in the second sequence for each prefix pair.
  --
  -- Matrices 2 and 3 are used in affine penalty calculation:
  -- gap penalty in the first sequence for the prefix (i, j) is gapOpen + M2[i, j] * gapExtend
  --
  -- The resulting score is the same as in plain gap penalty:
  -- the biggest one between substitution, insertion and deletion scores.
  --
-------------------

instance SequenceAlignment (GlobalAlignment AffineGap) where
    -- The alignment uses affine gap penalty
    {-# INLINE affine #-}
    affine = const True
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond (GlobalAlignment subC gap) = Conditions defStop (defDiag subC) (affVert gap) (affHoriz gap)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const defStart

    -- Next cell = max (d_i-1,j + gap, d_i,j-1 + gap, d_i-1,j-1 + s(i,j))
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => GlobalAlignment AffineGap (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist (GlobalAlignment subC AffineGap {..}) mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute subC s t

        gapCost :: Int -> Int
        gapCost 0 = gapOpen
        gapCost _ = gapExtend

        (lowerS, upperS) = bounds s
        (lowerT, upperT) = bounds t

        -- Replacement cost at prefixes (i, j)
        replacement :: Int
        replacement = mat ! (pred i, pred j, Match) + sub i j

        -- Number of insertions in the `s` sequence on prefixes (i - 1, j)
        insertions :: Int
        insertions  = mat ! (pred i,      j, Insert)

        -- Number of deletions in the `s` sequence on prefixes (i, j - 1)
        deletions :: Int
        deletions   = mat ! (     i, pred j, Delete)

        -- Insertion cost at prefixes (i, j)
        insertion :: Int
        insertion   = mat ! (pred i,      j, Match) + gapCost insertions

        -- Deletion cost at prefixes (i, j)
        deletion :: Int
        deletion    = mat ! (     i, pred j, Match) + gapCost deletions

        maxIxValue :: Int
        maxIxValue = maximum [replacement, insertion, deletion]

        result :: Int
        result = if | i == lowerS -> gapOpen + gapExtend * index (lowerT, succ upperT) j
                    | j == lowerT -> gapOpen + gapExtend * index (lowerS, succ upperS) i
                    | k == Insert -> if maxIxValue == insertion then succ insertions else 0
                    | k == Delete -> if maxIxValue == deletion then succ deletions else 0
                    | otherwise -> maxIxValue


instance SequenceAlignment (LocalAlignment AffineGap) where
    -- The alignment uses affine gap penalty
    {-# INLINE affine #-}
    affine = const True
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond (LocalAlignment subC gap) = Conditions localStop (defDiag subC) (affVert gap) (affHoriz gap)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const localStart
    -- Next cell = max (d_i-1,j + gap, d_i,j-1 + gap, d_i-1,j-1 + s(i,j))
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => LocalAlignment AffineGap (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist (LocalAlignment subC AffineGap{..}) mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute subC s t

        gapCost :: Int -> Int
        gapCost 0 = gapOpen
        gapCost _ = gapExtend

        (lowerS, _) = bounds s
        (lowerT, _) = bounds t

        replacement :: Int
        replacement = mat ! (pred i, pred j, Match) + sub i j

        insertions :: Int
        insertions  = mat ! (pred i,      j, Insert)
        deletions :: Int
        deletions   = mat ! (     i, pred j, Delete)

        insertion :: Int
        insertion   = mat ! (pred i,      j, Match) + gapCost insertions
        deletion :: Int
        deletion    = mat ! (     i, pred j, Match) + gapCost deletions

        maxIxValue :: Int
        maxIxValue = maximum [replacement, insertion, deletion, 0]

        result :: Int
        result = if | i == lowerS -> 0
                    | j == lowerT -> 0
                    | k == Insert -> if maxIxValue == insertion then succ insertions else 0
                    | k == Delete -> if maxIxValue == deletion then succ deletions else 0
                    | otherwise -> maxIxValue

instance SequenceAlignment (SemiglobalAlignment AffineGap) where
    -- The alignment uses affine gap penalty
    {-# INLINE affine #-}
    affine = const True
    -- The alignment is semiglobal, so we have to perform some additional operations
    {-# INLINE semi #-}
    semi = const True
    -- Conditions of traceback are described below
    {-# INLINE cond #-}
    cond (SemiglobalAlignment subC gap) = Conditions defStop (defDiag subC) (affVert gap) (affHoriz gap)
    -- Start from bottom right corner
    {-# INLINE traceStart #-}
    traceStart = const semiStart
    -- Next cell = max (d_i-1,j + gap, d_i,j-1 + gap, d_i-1,j-1 + s(i,j))
    {-# INLINE dist #-}
    dist :: forall m m' . (Alignable m, Alignable m')
         => SemiglobalAlignment AffineGap (IxValue m) (IxValue m')
         -> Matrix m m'
         -> m
         -> m'
         -> (Index m, Index m', EditOp)
         -> Int
    dist (SemiglobalAlignment subC AffineGap{..}) mat s t (i, j, k) = result
      where
        sub :: Index m -> Index m' -> Int
        sub = substitute subC s t

        gapCost :: Int -> Int
        gapCost 0 = gapOpen
        gapCost _ = gapExtend

        (lowerS, _) = bounds s
        (lowerT, _) = bounds t

        replacement :: Int
        replacement = mat ! (pred i, pred j, Match) + sub i j

        insertions :: Int
        insertions  = mat ! (pred i,      j, Insert)
        deletions :: Int
        deletions   = mat ! (     i, pred j, Delete)

        insertion :: Int
        insertion   = mat ! (pred i,      j, Match) + gapCost insertions
        deletion :: Int
        deletion    = mat ! (     i, pred j, Match) + gapCost deletions

        maxIxValue :: Int
        maxIxValue = maximum [replacement, insertion, deletion]

        result :: Int
        result = if | i == lowerS -> 0
                    | j == lowerT -> 0
                    | k == Insert -> if maxIxValue == insertion then succ insertions else 0
                    | k == Delete -> if maxIxValue == deletion then succ deletions else 0
                    | otherwise -> maxIxValue
