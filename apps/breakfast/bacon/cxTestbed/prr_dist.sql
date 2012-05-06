.mode csv
SELECT 
  a.src as src, 
  a.dest as dest, 
  a.prr as src_to_dest, 
  b.prr as dest_to_src 
  FROM final_prr_no_startup a JOIN final_prr_no_startup b
  ON a.src == b.dest and a.dest == b.src 
  WHERE a.src ==0;