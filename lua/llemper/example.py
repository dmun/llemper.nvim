'''''''''
function: flagAllNeighbors
----------
This function marks each of the covered neighbors of the cell at the given row
and col as flagged.
'''''''''
def flagAllNeighbors(board, row, col): 
  for r, c in b.getNeighbors(row, col):
  if b.isValid(r, c):
  b.flag(r, c)
  

